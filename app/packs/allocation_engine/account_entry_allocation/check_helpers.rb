module AccountEntryAllocation
  # The building blocks of a fund's pre/post-run checks, callable by name inside a PreRunCheck or
  # PostRunCheck formula (mixed into CheckContext):
  #
  #   allowed_entry_names("Non Deal Expense", ["Management Fees", "Audit Fees"])
  #
  # Each helper returns a CheckContext::Passed when nothing is wrong and otherwise raises
  # CheckFailed (or CheckWarning with severity: :warning) carrying the offending rows, so the
  # report shows the records behind a failure rather than a sentence about them.
  #
  # Why helpers rather than hand-written formulas: they get the traps right once --
  #   - "uploaded" is generated: false in the run's period. Pre-run checks run before the engine
  #     deletes its old output, so without the generated filter they would inspect the previous
  #     run's entries too.
  #   - Names and entry types are matched exactly, but MySQL's default collation compares and
  #     groups case-insensitively, so exactness is enforced with BINARY grouping plus a Ruby
  #     comparison (see #exact_groups).
  #   - account_entries is huge: helpers aggregate in SQL and read narrow columns only.
  #   - Messages are built here, outside the formula text, so words the eval blocklist refuses
  #     ("updated", "created") can appear in them.
  #
  # See docs/modules/allocation/allocation_run_checks.md.
  module CheckHelpers
    SEVERITIES = %i[fail warning].freeze
    ROW_LIMIT = AllocationRunReport::MAX_ROWS_PER_FINDING

    # Rule types that allocate fund-level account entries to folios (see RunFormula's dispatch),
    # and which entry attribute each one selects by. "AllocateAccountEntry" is the legacy spelling
    # of the -Name variant; RunFormula still dispatches it.
    ENTRY_ALLOCATION_SELECTORS = {
      "AllocateAccountEntry" => :name,
      "AllocateAccountEntry-Name" => :name,
      "AllocateAccountEntryIndividual-Name" => :name,
      "AllocateAccountEntry-EntryType" => :entry_type,
      "AllocateAccountEntryIndividual-EntryType" => :entry_type
    }.freeze

    # Default tolerance for tie-out checks, in the fund's currency (major units). Each folio's share
    # of a fund-level amount is rounded, so the shares of a fund with N folios can legitimately
    # drift from the total by up to about N x 0.005; 1.00 is immaterial at fund level.
    DEFAULT_TOLERANCE = 1.0

    # P1/P2: every uploaded entry of entry_type is named one of names.
    #   allowed_entry_names("Non Deal Income", ["Income from Temporary Investments", "Miscelleneous Income"])
    def allowed_entry_names(entry_type, names, severity: :fail)
      allowed = names.to_set
      groups = exact_groups(uploaded_entries.where(entry_type:), :entry_type, :name)
      offenders = groups.select { |(type, name), _| type == entry_type && allowed.exclude?(name) }

      if offenders.empty?
        checked = groups.sum { |(type, _), stats| type == entry_type ? stats[:count] : 0 }
        return passed("No #{entry_type} entries were uploaded for this period.") if checked.zero?

        return passed("All #{checked} uploaded #{entry_type} #{'entry'.pluralize(checked)} use an allowed name.")
      end

      rows = offenders.map { |(_, name), stats| [name, stats[:count], money(stats[:amount_cents])] }
      filters = offenders.map { |(_, name), _| uploaded_filter(["entry_type", :eq, entry_type], ["name", :eq, name]) }
      check_problem(severity, "#{offenders.size} uploaded #{entry_type} #{'name'.pluralize(offenders.size)} " \
                              "#{offenders.size == 1 ? 'is' : 'are'} not in the allowed list.",
                    columns: ["Entry name", "Entries", "Total amount"], rows:, filters:)
    end

    # P3/P4: every uploaded entry (target :account_entries) or every portfolio investment dated in
    # the period (target :portfolio_investments, proforma included) has a value for each custom
    # field. Labels are the custom field labels as shown on screen and in import headers.
    #   required_custom_fields(:account_entries, ["Fund Level UDR Code", "Expense Head"])
    #
    # For account entries the check can be narrowed to the entries that actually need the fields:
    #   fund_level_only: true  -- only fund-level uploads. Allocation formulas read custom fields
    #                             (e.g. fund_level_udr_code) off the fund-level entry they allocate;
    #                             folio-level uploads such as per-folio taxes are never allocated.
    #   entry_types: [...]     -- only uploads of these entry types, matched exactly.
    #   required_custom_fields(:account_entries, ["Fund Level UDR Code"], fund_level_only: true)
    def required_custom_fields(target, labels, fund_level_only: false, entry_types: nil, severity: :fail)
      raise ArgumentError, "fund_level_only: and entry_types: only apply to :account_entries" if target != :account_entries && (fund_level_only || entry_types)

      model, scope, describe = custom_field_target(target)
      keys = custom_field_keys(model, labels)
      wanted_types = entry_types && Array(entry_types).to_set
      scope = scope.where(capital_commitment_id: nil) if fund_level_only
      scope = scope.where(entry_type: wanted_types.to_a) if wanted_types
      noun = describe[:noun]
      noun = noun.sub("uploaded entries", "uploaded fund-level entries") if fund_level_only
      noun = "#{noun} of type #{wanted_types.to_a.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}" if wanted_types

      checked = 0
      missing_count = 0
      rows = []
      filters = []
      each_json_fields_batch(scope, describe[:columns]) do |values, json|
        # SQL matched entry_type ignoring case (MySQL collation); the check matches it exactly.
        next if wanted_types&.exclude?(values[describe[:columns].index(:entry_type)])

        checked += 1
        missing = labels.zip(keys).filter_map { |label, key| label if json[key].blank? && json[key] != false }
        next if missing.empty?

        missing_count += 1
        next if rows.size >= ROW_LIMIT

        rows << (describe[:row].call(values) + [missing.join(", ")])
        filters << describe[:filter]&.call(values)
      end

      fields = labels.size == 1 ? "the required custom field" : "all #{labels.size} required custom fields"
      return passed("There are no #{noun} to check.") if checked.zero?
      return passed("#{checked} #{noun} checked; every one has #{fields}.") if missing_count.zero?

      check_problem(severity, "#{missing_count} of #{checked} #{noun} " \
                              "#{missing_count == 1 ? 'is' : 'are'} missing required custom fields.",
                    columns: describe[:headers] + ["Missing fields"], rows:, filters:,
                    truncated: missing_count - rows.size)
    end

    # P5: every uploaded entry of these entry types is mapped (parent) to one of this fund's
    # portfolio investments. A portfolio company as parent does not count.
    #   entries_mapped_to_portfolio_investment(["Deal Expense", "Deal Expense Capitalized", "Deal income"])
    def entries_mapped_to_portfolio_investment(entry_types, severity: :fail)
      entry_types = Array(entry_types)
      base = uploaded_entries.where(entry_type: entry_types)
      fund_investments = PortfolioInvestment.include_proforma.where(fund_id: @fund.id).select(:id)
      unmapped = base.where(parent_type: nil)
                     .or(base.where.not(parent_type: "PortfolioInvestment"))
                     .or(base.where(parent_id: nil))
                     .or(base.where.not(parent_id: fund_investments))

      wanted = entry_types.to_set
      offenders = unmapped.order(:reporting_date, :id)
                          .pluck(:entry_type, :name, :reporting_date, :amount_cents, :parent_type, :parent_id, :parent_name)
                          .select { |type, *| wanted.include?(type) } # exact entry type, see #exact_groups

      if offenders.empty?
        checked = exact_groups(base, :entry_type).sum { |(type), stats| wanted.include?(type) ? stats[:count] : 0 }
        return passed("No #{entry_types.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')} entries were uploaded for this period.") if checked.zero?

        return passed("All #{checked} uploaded deal #{'entry'.pluralize(checked)} are mapped to a portfolio investment of this fund.")
      end

      shown = offenders.first(ROW_LIMIT)
      rows = shown.map do |type, name, date, cents, parent_type, parent_id, parent_name|
        [name, type, I18n.l(date), money(cents), current_mapping(parent_type, parent_id, parent_name)]
      end
      filters = shown.map do |type, name, date, *|
        uploaded_filter(["entry_type", :eq, type], ["name", :eq, name], ["reporting_date", :eq, date.to_fs(:db)])
      end
      check_problem(severity, "#{offenders.size} uploaded deal #{'entry'.pluralize(offenders.size)} " \
                              "#{offenders.size == 1 ? 'is' : 'are'} not mapped to a portfolio investment of this fund.",
                    columns: ["Entry name", "Entry type", "Reporting date", "Amount", "Currently mapped to"],
                    rows:, filters:, truncated: offenders.size - shown.size)
    end

    # P6: a rate dated within within_days before the end date for every currency pair the fund
    # needs -- the same pairs as the allocation_run_fx_rates_exist validation rule.
    # The window is within_days, or within_months calendar months (3 months before 31 Aug is 31 May).
    #   fx_rates_present(within_months: 3)
    def fx_rates_present(within_days: 5, within_months: nil, severity: :fail)
      n_days, window = check_window(within_days, within_months)
      readiness = AllocationRunReadiness.new(fund: @fund, entity_id: @fund.entity_id, end_date: @end_date, n_days:)
      missing = readiness.missing_fx_rates
      return passed("This fund needs no foreign exchange rate.") if missing.nil?
      return passed("Every exchange rate this fund needs is dated within #{window} before #{I18n.l(@end_date)}.") if missing.empty?

      rows = missing.map do |(from, to), labels|
        [from, to, labels.join(", "), readiness.latest_fx_rate_date(from, to)&.then { |d| I18n.l(d) } || "None"]
      end
      check_problem(severity, "#{missing.size} exchange #{'rate'.pluralize(missing.size)} #{missing.size == 1 ? 'has' : 'have'} " \
                              "no rate dated within #{window} before #{I18n.l(@end_date)}.",
                    columns: ["From", "To", "Needed by", "Latest rate"], rows:)
    end

    # P7: a valuation dated within within_days before the end date for every portfolio company the
    # fund holds -- the same rule as the allocation_run_valuation_exists validation rule.
    #   valuations_present(within_days: 30, severity: :warning)
    def valuations_present(within_days: 30, within_months: nil, severity: :fail)
      n_days, window = check_window(within_days, within_months)
      readiness = AllocationRunReadiness.new(fund: @fund, entity_id: @fund.entity_id, end_date: @end_date, n_days:)
      missing = readiness.missing_valuation_companies
      return passed("This fund holds no portfolio position at #{I18n.l(@end_date)}.") if missing.nil?
      return passed("Every portfolio company held has a valuation dated within #{window} before #{I18n.l(@end_date)}.") if missing.empty?

      latest = readiness.latest_valuation_dates(missing.map(&:first))
      rows = missing.map { |id, name| [name, latest[id]&.then { |d| I18n.l(d) } || "None"] }
      check_problem(severity, "#{missing.size} portfolio #{'company'.pluralize(missing.size)} #{missing.size == 1 ? 'has' : 'have'} " \
                              "no valuation dated within #{window} before #{I18n.l(@end_date)}.",
                    columns: ["Portfolio company", "Latest valuation"], rows:)
    end

    # Q1: every uploaded fund-level entry was picked up by an allocation formula that ran in this
    # run. Entries are grouped by exact name and entry type.
    #
    # "Picked up" is decided the way the engine picks: an AllocateAccountEntry*-Name formula takes
    # every fund-level entry in the period named after it, an -EntryType formula every one of its
    # entry type. A group counts as allocated when such a formula wrote folio entries in this run.
    # It is not decided by parent links: a folio entry is a dup of the fund-level entry, so it
    # inherits that entry's own parent (a deal expense keeps its portfolio investment) and only
    # points back at the fund-level entry when that entry had no parent.
    #   fund_entries_allocated(except: ["Opening Cash Balance"])
    def fund_entries_allocated(except: [], severity: :fail)
      run_id! # before any early return, so misuse as a pre-run check always fails
      excluded = except.to_set
      groups = exact_groups(uploaded_entries.where(capital_commitment_id: nil), :name, :entry_type)
               .reject { |(name, _), _| excluded.include?(name) }
      return passed("No fund-level entries were uploaded for this period.") if groups.empty?

      ran = allocation_formulas_that_ran
      offenders = groups.reject do |(name, entry_type), _|
        ran.any? { |formula, selector| formula.name == (selector == :name ? name : entry_type) }
      end
      return passed("#{groups.size} uploaded fund-level entry #{'name'.pluralize(groups.size)} checked; every one was allocated to folios.") if offenders.empty?

      rows = offenders.map { |(name, entry_type), stats| [name, entry_type, stats[:count], money(stats[:amount_cents])] }
      filters = offenders.map { |(name, entry_type), _| uploaded_filter(["name", :eq, name], ["entry_type", :eq, entry_type]) }
      check_problem(severity, "#{offenders.size} uploaded fund-level entry #{'name'.pluralize(offenders.size)} " \
                              "#{offenders.size == 1 ? 'was' : 'were'} not allocated to folios by any formula in this run.",
                    columns: ["Entry name", "Entry type", "Entries", "Total amount"], rows:, filters:)
    end

    # Q2: for every allocation formula that ran, the fund-level entries it picked up add up to what
    # it allocated to the folios, name by name, within tolerance (fund currency, major units).
    #
    # "Picked up" is every fund-level entry in the period matching the formula's selector that this
    # run did not write itself -- uploaded or generated, because that is what the formula allocated.
    # "Allocated" is this run's non-cumulative folio entries from that formula under the same name;
    # the Quarterly/YTD/Since Inception entries generate_ytd_qtly adds carry prefixed names and so
    # never count. Names in except: are left out, for entries a fund allocates only in part on
    # purpose. Groups that were never allocated at all are fund_entries_allocated's to report.
    def fund_entries_tie_to_folios(tolerance: DEFAULT_TOLERANCE, except: [], severity: :fail)
      run_id! # before any early return, so misuse as a pre-run check always fails
      excluded = except.to_set
      ran = allocation_formulas_that_ran
      return passed("No account entry allocation formula wrote entries in this run.") if ran.empty?

      source = exact_groups(fund_level_entries_not_from_this_run, :name, :entry_type)
      allocated = exact_groups(run_folio_entries.where(fund_formula_id: ran.keys.map(&:id)), :fund_formula_id, :name)
                  .to_h { |(formula_id, name), stats| [[formula_id.to_i, name], stats[:amount_cents]] }

      compared = 0
      mismatches = []
      ran.each do |formula, selector|
        picked = source.select { |(name, entry_type), _| (selector == :name ? name : entry_type) == formula.name }
        picked.group_by { |(name, _), _| name }.each do |name, name_groups|
          next if excluded.include?(name)

          compared += 1
          fund_total = name_groups.sum { |_, stats| stats[:amount_cents] || 0 }
          allocated_total = allocated.fetch([formula.id, name], 0)
          difference = fund_total - allocated_total
          next if difference.abs <= tolerance.to_d * 100

          mismatches << [formula, name, fund_total, allocated_total, difference]
        end
      end

      return passed("No fund-level entries were picked up by the allocation formulas that ran.") if compared.zero?
      return passed("#{compared} allocated fund-level #{'total'.pluralize(compared)} checked; every one matches the folio entries within #{money(tolerance.to_d * 100)}.") if mismatches.empty?

      shown = mismatches.first(ROW_LIMIT)
      rows = shown.map { |formula, name, fund_total, allocated_total, difference| [formula.name, name, money(fund_total), money(allocated_total), money(difference)] }
      filters = shown.map { |formula, name, *| run_filter(["fund_formula_id", :eq, formula.id], ["name", :eq, name]) }
      check_problem(severity, "#{mismatches.size} of #{compared} fund-level #{'total'.pluralize(compared)} " \
                              "#{mismatches.size == 1 ? 'does' : 'do'} not match what was allocated to the folios " \
                              "(tolerance #{money(tolerance.to_d * 100)}).",
                    columns: ["Formula", "Entry name", "Fund level", "Allocated to folios", "Difference"],
                    rows:, filters:, truncated: mismatches.size - shown.size)
    end

    # Q3: for each named AllocatePortfolioInvestment* formula, every portfolio investment's amount
    # column equals what the formula allocated to the folios for that investment, within tolerance.
    #   portfolio_allocations_tie("Investment Amount" => :amount_cents, "Cost Of Sold" => :cost_of_sold_cents)
    #
    # The investments compared are exactly the ones the formula allocates -- same fund or master
    # fund, proforma or not, and the between_start_and_end_dates / where settings in its meta_data
    # (AllocatePortfolioInvestments.portfolio_investments_for). Allocated entries are found by this
    # run's id, not by date, since meta_data can date them on the investment date.
    #
    # The mapping arrives through **pairs as well as positionally: written without braces, as a
    # formula naturally would, Ruby passes `"Name" => :column` as keywords because the method
    # also takes tolerance:/severity:, and a plain positional hash parameter would raise.
    def portfolio_allocations_tie(mapping = {}, tolerance: DEFAULT_TOLERANCE, severity: :fail, **pairs)
      run_id! # before any early return, so misuse as a pre-run check always fails
      mapping = mapping.merge(pairs).transform_keys(&:to_s)
      raise ArgumentError, "portfolio_allocations_tie needs at least one \"Formula name\" => :amount_column pair" if mapping.blank?

      formulas = portfolio_allocation_formulas(mapping.keys)
      compared = 0
      mismatches = []
      mapping.each do |formula_name, column|
        column = portfolio_amount_column(column)
        formula = formulas.fetch(formula_name)
        options = AllocatePortfolioInvestments::RULE_TYPE_OPTIONS.fetch(formula.rule_type)
        investments = AllocatePortfolioInvestments.portfolio_investments_for(@fund, formula, start_date: @start_date, end_date: @end_date, **options)
        allocated = run_folio_entries.where(fund_formula_id: formula.id, name: formula.name, parent_type: "PortfolioInvestment")
                                     .group(:parent_id).sum(:amount_cents)

        investments.pluck(:id, column, :portfolio_company_name, :investment_date).each do |id, expected, company, date|
          compared += 1
          allocated_total = allocated.fetch(id, 0)
          difference = (expected || 0) - allocated_total
          next if difference.abs <= tolerance.to_d * 100

          mismatches << [formula, column, id, company, date, expected, allocated_total, difference]
        end
      end

      return passed("There were no portfolio investments for these formulas to allocate.") if compared.zero?
      return passed("#{compared} portfolio investment #{'amount'.pluralize(compared)} checked; every one matches the folio entries within #{money(tolerance.to_d * 100)}.") if mismatches.empty?

      shown = mismatches.first(ROW_LIMIT)
      rows = shown.map do |formula, column, _id, company, date, expected, allocated_total, difference|
        [formula.name, "#{company} (#{I18n.l(date)})", column.to_s.delete_suffix("_cents").humanize, money(expected), money(allocated_total), money(difference)]
      end
      filters = shown.map { |formula, _column, id, *| run_filter(["fund_formula_id", :eq, formula.id], ["parent_type", :eq, "PortfolioInvestment"], ["parent_id", :eq, id]) }
      check_problem(severity, "#{mismatches.size} of #{compared} portfolio investment #{'amount'.pluralize(compared)} " \
                              "#{mismatches.size == 1 ? 'does' : 'do'} not match what was allocated to the folios " \
                              "(tolerance #{money(tolerance.to_d * 100)}).",
                    columns: ["Formula", "Portfolio investment", "Amount", "Investment", "Allocated to folios", "Difference"],
                    rows:, filters:, truncated: mismatches.size - shown.size)
    end

    private

    # [days before the end date, how to say it] for the FX rate and valuation windows.
    def check_window(within_days, within_months)
      return [within_days.to_i, "#{within_days} #{'day'.pluralize(within_days.to_i)}"] unless within_months

      [(@end_date - (@end_date - within_months.to_i.months)).to_i, "#{within_months} #{'month'.pluralize(within_months.to_i)}"]
    end

    # Post-run helpers compare against what this run wrote, so they need the run.
    def run_id!
      @allocation_run&.id || raise(ArgumentError, "This check compares against the allocation run's own entries, so it can only be a PostRunCheck")
    end

    # Folio-level, non-cumulative entries this run wrote.
    def run_folio_entries
      AccountEntry.where(fund_id: @fund.id, allocation_run_id: run_id!, cumulative: false, deleted_at: nil)
                  .where.not(capital_commitment_id: nil)
    end

    # Fund-level entries in the period that this run did not write: what an allocation formula saw.
    def fund_level_entries_not_from_this_run
      run_id = run_id!
      scope = AccountEntry.where(fund_id: @fund.id, capital_commitment_id: nil, reporting_date: @start_date..@end_date, deleted_at: nil)
      scope.where(allocation_run_id: nil).or(scope.where.not(allocation_run_id: run_id))
    end

    # { FundFormula => :name | :entry_type } for this fund's entry allocation formulas that wrote
    # folio entries in this run. Found from the entries, so a formula counts whether or not it is
    # enabled or in scope today -- what matters is that it ran.
    def allocation_formulas_that_ran
      @allocation_formulas_that_ran ||= begin
        formulas = FundFormula.where(fund_id: @fund.id, rule_type: ENTRY_ALLOCATION_SELECTORS.keys).index_by(&:id)
        ran_ids = formulas.empty? ? [] : run_folio_entries.where(fund_formula_id: formulas.keys).distinct.pluck(:fund_formula_id)
        ran_ids.to_h { |id| [formulas[id], ENTRY_ALLOCATION_SELECTORS.fetch(formulas[id].rule_type)] }
      end
    end

    # { name => FundFormula } for the portfolio allocation formulas named in a mapping, matched
    # exactly; a name that does not resolve fails the check rather than silently comparing nothing.
    def portfolio_allocation_formulas(names)
      candidates = FundFormula.where(fund_id: @fund.id, name: names, rule_type: AllocatePortfolioInvestments::RULE_TYPE_OPTIONS.keys).to_a
      names.to_h do |name|
        matches = candidates.select { |f| f.name == name }
        raise ArgumentError, "No portfolio investment allocation formula named #{name.inspect} in this fund" if matches.empty?
        raise ArgumentError, "#{matches.size} portfolio investment allocation formulas are named #{name.inspect}; names must be unique" if matches.size > 1

        [name, matches.first]
      end
    end

    def portfolio_amount_column(column)
      column = column.to_s
      return column if column.end_with?("_cents") && PortfolioInvestment.column_names.include?(column)

      raise ArgumentError, "#{column.inspect} is not a portfolio investment amount column (expected e.g. :amount_cents, :cost_of_sold_cents)"
    end

    # Filter triples for this run's entries, narrowed further by extra.
    def run_filter(*extra)
      [["fund_id", :eq, @fund.id], ["allocation_run_id", :eq, run_id!], *extra.compact]
    end

    # Entries loaded by upload or by hand -- anything the engine did not generate -- dated in the
    # run's period, at fund and folio level.
    def uploaded_entries
      AccountEntry.where(fund_id: @fund.id, generated: false, reporting_date: @start_date..@end_date, deleted_at: nil)
    end

    # Groups scope by the given string columns *exactly* and returns
    # { [col values...] => { count:, amount_cents: } }.
    #
    # A plain GROUP BY / DISTINCT on MySQL's default collation folds "Audit Fees" and "audit fees"
    # into one group reported under either spelling, and `where(name: ...)` matches regardless of
    # case -- so an entry named "audit fees" would pass an allowed list containing "Audit Fees".
    # Grouping on a binary comparison keeps every byte-distinct spelling apart; MIN() of such a group
    # is its one exact value. SQLite needs it too: its default is case-sensitive, but a column can be
    # declared NOCASE -- account_entries.name is, in db/schema_test.rb -- and GROUP BY follows the
    # column's collation.
    def exact_groups(scope, *columns)
      exprs = columns.map { |c| exact_column(scope.klass, c) }
      picks = columns.map { |c| Arel.sql("MIN(#{scope.klass.quoted_table_name}.#{scope.klass.connection.quote_column_name(c)})") }
      scope.group(*exprs.map { |e| Arel.sql(e) })
           .pluck(*picks, Arel.sql("COUNT(*)"), Arel.sql("SUM(#{scope.klass.quoted_table_name}.amount_cents)"))
           .to_h { |row| [row.first(columns.size), { count: row[columns.size].to_i, amount_cents: row[columns.size + 1] || 0 }] }
    end

    def exact_column(klass, column)
      qualified = "#{klass.quoted_table_name}.#{klass.connection.quote_column_name(column)}"
      adapter = klass.connection.adapter_name.downcase
      if adapter.match?(/mysql|trilogy/)
        "BINARY #{qualified}"
      elsif adapter.include?("sqlite")
        "#{qualified} COLLATE BINARY"
      else
        qualified
      end
    end

    # [model, scope, how to describe a record] for required_custom_fields.
    def custom_field_target(target)
      case target
      when :account_entries
        [AccountEntry, uploaded_entries,
         # entry_type is plucked last only so entry_types: can be matched exactly; rows ignore it.
         { noun: "uploaded entries", columns: %i[name reporting_date folio_id entry_type],
           headers: ["Entry name", "Reporting date", "Folio"],
           row: ->((name, date, folio)) { [name, I18n.l(date), folio.presence || "Fund level"] },
           filter: ->((name, date, folio)) { uploaded_filter(["name", :eq, name], ["reporting_date", :eq, date.to_fs(:db)], (["folio_id", :eq, folio] if folio.present?)) } }]
      when :portfolio_investments
        [PortfolioInvestment,
         PortfolioInvestment.include_proforma.where(fund_id: @fund.id, investment_date: @start_date..@end_date),
         { noun: "portfolio investments dated in the period", columns: %i[portfolio_company_name investment_date quantity],
           headers: ["Portfolio company", "Investment date", "Quantity"],
           row: ->((company, date, quantity)) { [company, I18n.l(date), quantity&.to_s] },
           # The report links rows to the account entries screen; there is no investments equivalent.
           filter: nil }]
      else
        raise ArgumentError, "required_custom_fields target must be :account_entries or :portfolio_investments, not #{target.inspect}"
      end
    end

    # Custom field label -> json_fields key, resolved the way imports resolve it
    # (ImportUtil#setup_custom_fields): the entity's form custom field with that label, else the
    # name derived from the label.
    def custom_field_keys(model, labels)
      by_label = FormCustomField.joins(:form_type)
                                .where(form_types: { entity_id: @fund.entity_id, name: model.name })
                                .pluck(:label, :name)
                                .to_h { |label, name| [label.to_s.downcase, name] }
      labels.map { |label| by_label[label.downcase] || FormCustomField.to_name(label) }
    end

    # Yields ([columns values], json_fields Hash) for every record in scope, keyset-batched by id
    # and plucking only the described columns plus json_fields -- never whole rows. AccountEntry
    # ids are unique despite its composite primary key (see CLAUDE.md), so id batching is safe.
    def each_json_fields_batch(scope, columns, batch_size: 2_000)
      table = scope.klass.quoted_table_name
      last_id = 0
      loop do
        batch = scope.where("#{table}.id > ?", last_id).reorder(:id).limit(batch_size).pluck(:id, *columns, :json_fields)
        break if batch.empty?

        batch.each do |id, *values, json|
          json = JSON.parse(json) if json.is_a?(String)
          yield values, json || {}
          last_id = id
        end
        break if batch.size < batch_size
      end
    end

    def current_mapping(parent_type, parent_id, parent_name)
      return "Nothing" if parent_type.blank? || parent_id.blank?
      return "Portfolio investment of another fund (#{parent_name.presence || "##{parent_id}"})" if parent_type == "PortfolioInvestment"

      "#{parent_type.titleize}: #{parent_name.presence || "##{parent_id}"}"
    end

    # [field, predicate, value] triples for AllocationRunReportsHelper#finding_entries_path: the
    # uploaded entries of this run's period, narrowed further by extra.
    def uploaded_filter(*extra)
      [["fund_id", :eq, @fund.id], ["generated", :eq, false],
       ["reporting_date", :gteq, @start_date.to_fs(:db)], ["reporting_date", :lteq, @end_date.to_fs(:db)],
       *extra.compact]
    end

    def money(cents)
      ActiveSupport::NumberHelper.number_to_rounded((cents || 0).to_d / 100, precision: 2, delimiter: ",")
    end

    def passed(summary)
      CheckContext::Passed.new(summary)
    end

    def check_problem(severity, summary, columns:, rows:, filters: [], truncated: 0)
      raise ArgumentError, "severity must be one of #{SEVERITIES.inspect}, not #{severity.inspect}" unless SEVERITIES.include?(severity)

      error_class = severity == :warning ? CheckWarning : CheckFailed
      raise error_class.new(summary, columns:, rows:, filters:, truncated: [truncated, 0].max)
    end
  end
end
