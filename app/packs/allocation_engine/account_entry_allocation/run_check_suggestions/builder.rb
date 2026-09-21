module AccountEntryAllocation
  # Suggests pre/post-run check formulas for a fund. See docs/modules/allocation/allocation_run_checks.md
  # and openspec/changes/incremental-allocation-ui.
  module RunCheckSuggestions
    # The rule-based suggester: fixed rules that read the fund's formula text (the same regex approach as
    # IncrementalMigration) and its data, each producing helper-call checks with the evidence that led
    # to them. The same fund data always produces the same suggestions.
    #
    #   builder = Builder.new(fund)
    #   suggestions = builder.suggestions          # marked already present / similar, validated
    #   builder.test_run(suggestions)              # evaluated against the last successful run
    class Builder
      # A total by name: quarterly("Audit Fees", ...), year_to_date(...), since_inception(...)
      NAMED_TOTAL = /\b(?:quarterly|year_to_date|since_inception)\(\s*"([^"]+)"/
      # A literal array of strings: ["Audit Fees", "Bank Charges"]
      STRING_ARRAY = /\[\s*"[^"\]]*"(?:\s*,\s*"[^"\]]*")*\s*\]/
      ENTRY_FIELD = /fund_account_entry\.json_fields\[\s*['"](\w+)['"]\s*\]/
      INVESTMENT_FIELD = /portfolio_investment\.json_fields\[\s*['"](\w+)['"]\s*\]/
      FOLIO_FIELD_READ = /capital_commitment\.json_fields\[/
      UNIT_SETTING_JSON = /fund_unit_setting\.json_fields\[\s*['"](\w+)['"]\s*\]/
      UNIT_SETTING_CALL = /fund_unit_setting&?\.(\w+)\b/
      INVESTMENT_AMOUNT = /portfolio_investment\.(\w+_cents)\b/
      # The amount allocated with its sign changed, so it cannot tie to the investment column sign for sign
      SIGN_FLIP = /\*\s*-\s*1\b|-\s*1\s*\*|-\s*\(?\s*portfolio_investment\./
      SINGLE_SINCE_INCEPTION = /\A\s*capital_commitment\.since_inception\(\s*"([^"]+)"\s*,\s*nil\s*,\s*@start_date\s*,\s*@end_date\s*(?:,[^)]*)?\)\s*\z/
      PORTFOLIO_ALLOCATION_TYPES = AllocatePortfolioInvestments::RULE_TYPE_OPTIONS.keys.freeze
      ENTRY_ALLOCATION_TYPES = CheckHelpers::ENTRY_ALLOCATION_SELECTORS.keys.freeze
      MAX_EVIDENCE_FORMULAS = 12

      attr_reader :context

      def initialize(fund)
        @context = Context.new(fund)
      end

      delegate :fund, to: :context

      # A formula reduced to what makes two checks the same: a helper call becomes its name plus its sorted
      # literals, so ["Audit Fees", "Bank Charges"] and ["Bank Charges", "Audit Fees"] compare equal (no
      # helper's result depends on list order); anything else compares on its text without spacing.
      def self.comparable(formula)
        text = formula.to_s.strip
        helper, args = Suggestion.helper_call(text)
        helper = text if helper.nil? && Suggestion::SEVERITY_HELPERS.include?(text) # a bare call, no parentheses
        return text.squish unless helper

        literals = args.to_s.scan(/"(?:[^"\\]|\\.)*"|:\w+|\w+:|-?\d+(?:\.\d+)?/)
        [helper, *literals.sort].join("|")
      end

      # @return [Array<Suggestion>]
      def suggestions
        list = allowed_names + required_fields + deal_mapping + folio_shares + unit_settings +
               fx_rates + valuations + entries_allocated + portfolio_tie + since_inception
        list.each { |s| annotate(s) }
      end

      # Marks a suggestion already present (same text as an existing check), notes existing checks calling
      # the same helper, and validates it as the FundFormula it would become.
      def annotate(suggestion)
        texts = [suggestion.formula(severity: "fail"), suggestion.formula(severity: "warning")].map { |t| self.class.comparable(t) }
        present = context.existing_checks.find { |ff| texts.include?(self.class.comparable(ff.formula)) }
        suggestion["already_present"] = present&.id
        suggestion["similar_to"] = if suggestion.helper.present? && present.nil?
                                     context.existing_checks.select { |ff| ff.formula.to_s.lstrip.start_with?("#{suggestion.helper}(", "#{suggestion.helper}\n") }
                                            .map { |ff| { "formula_id" => ff.id, "sequence" => ff.sequence, "name" => ff.name } }
                                   else
                                     []
                                   end
        formula = FundFormula.new(fund:, entity_id: fund.entity_id, name: suggestion.name, description: suggestion.description,
                                  rule_type: suggestion.rule_type, formula: suggestion.formula, rule_for: "accounting", enabled: true)
        suggestion["errors"] = formula.valid? ? [] : formula.errors.full_messages
        suggestion
      end

      UNTESTED_AI_SUMMARY = "Not tested: a formula written by AI is only evaluated once a person adds it. Read the text before adding.".freeze

      # Evaluates each valid suggestion, at its current severity, against run (by default the fund's last
      # successful allocation run) and stores the outcome on it. Changes no data. An AI suggestion that is
      # not a plain helper call with literal arguments is never evaluated here (Suggestion#safe_to_test?).
      def test_run(suggestions, run: context.last_successful_run)
        unless run
          suggestions.each { |s| s["result"] = { "result" => "not_tested", "summary" => "The fund has no successful allocation run to test against." } }
          return suggestions
        end

        testable, skipped = suggestions.partition { |s| s.errors.blank? && s.safe_to_test? }
        skipped.each do |s|
          s["result"] = { "result" => "not_tested", "summary" => s.errors.present? ? "Not tested: the formula is not valid." : UNTESTED_AI_SUMMARY }
        end
        testable.group_by(&:pre?).each do |pre, group|
          formulas = group.map do |s|
            FundFormula.new(fund:, entity_id: fund.entity_id, name: s.name, rule_type: s.rule_type, formula: s.formula, sequence: 0)
          end
          results = RunChecks.new(formulas, kind: pre ? :pre : :post, fund:, start_date: run.start_date, end_date: run.end_date, allocation_run: run).call
          group.zip(results).each do |s, r|
            s["result"] = r.slice("result", "summary", "columns", "rows", "truncated", "duration_ms")
                           .merge("run_id" => run.id, "start_date" => run.start_date.iso8601, "end_date" => run.end_date.iso8601)
          end
        end
        suggestions
      end

      private

      # --- Pre-run -------------------------------------------------------------------------------------

      # Per entry type an entry allocation formula allocates by: the names the fund's formulas total, as
      # the names that entry type may be uploaded under. A name counts when it is uploaded under that entry
      # type, or has never been uploaded but sits in the same literal list as one that is (e.g. an expense
      # head no one has booked yet). A name uploaded under the type but totalled by no formula is left out
      # on purpose: flagging it is what the check is for.
      def allowed_names
        refs = Hash.new { |h, k| h[k] = [] }
        arrays = []
        context.formulas.each do |ff|
          text = ff.formula.to_s
          text.scan(NAMED_TOTAL).flatten.each { |name| refs[name] << ff }
          text.scan(STRING_ARRAY).each do |literal|
            names = literal.scan(/"([^"]*)"/).flatten
            arrays << names
            names.each { |name| refs[name] << ff }
          end
        end
        uploaded_types = context.uploaded.group_by { |u| u[:name] }.transform_values { |rows| rows.to_set { |u| u[:entry_type] } }

        entry_type_allocations.filter_map do |entry_type, allocating|
          direct = refs.keys.select { |name| uploaded_types[name]&.include?(entry_type) }
          next if direct.empty?

          siblings = arrays.select { |names| names.intersect?(direct) }.flatten
                           .select { |name| uploaded_types[name].nil? || uploaded_types[name].include?(entry_type) }
          allowed = (direct + siblings).uniq.sort
          uploaded_names = context.uploaded.select { |u| u[:entry_type] == entry_type }.map { |u| u[:name] }.uniq.sort
          untotalled = uploaded_names - allowed

          evidence = formula_evidence(allowed.flat_map { |name| refs[name] }, "totals one of these names")
          evidence.unshift(*formula_evidence(allocating, "allocates every #{entry_type} entry by entry type"))
          evidence << fact("#{uploaded_names.size} #{'name'.pluralize(uploaded_names.size)} uploaded as #{entry_type}: #{uploaded_names.to_sentence}")
          evidence << fact("Uploaded as #{entry_type} but totalled by no formula: #{untotalled.to_sentence}") if untotalled.any?

          Suggestion.build(key: "rule:allowed_names:#{entry_type}", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                           name: "Pre-run check: #{entry_type} names",
                           description: "Every uploaded #{entry_type} entry must use one of the #{allowed.size} names the fund's formulas total. " \
                                        "An entry under any other name is still allocated, but no Quarterly, YTD or Since Inception formula " \
                                        "adds it up, so it never reaches the totals the statements and NAV read. Names are matched exactly.",
                           helper: "allowed_entry_names", args: "#{entry_type.inspect}, #{allowed.inspect}", evidence:)
        end
      end

      # The custom fields allocation formulas read off the fund-level entry or the portfolio investment they
      # allocate. A blank value does not raise: the formula builds an empty folio field name and allocates zero.
      def required_fields
        [[ENTRY_FIELD, ENTRY_ALLOCATION_TYPES, :account_entries, "AccountEntry", "fund-level uploads", ", fund_level_only: true"],
         [INVESTMENT_FIELD, PORTFOLIO_ALLOCATION_TYPES, :portfolio_investments, "PortfolioInvestment", "portfolio investments dated in the period", ""]]
          .filter_map do |pattern, rule_types, target, model, noun, options|
          readers = Hash.new { |h, k| h[k] = [] }
          context.formulas.select { |ff| rule_types.include?(ff.rule_type) }.each do |ff|
            ff.formula.to_s.scan(pattern).flatten.uniq.each { |key| readers[key] << ff }
          end
          next if readers.empty?

          labels = readers.keys.sort.map { |key| custom_field_label(model, key) }
          Suggestion.build(key: "rule:required_fields:#{target}", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                           name: "Pre-run check: #{target.to_s.humanize} custom fields",
                           description: "Every one of the #{noun} must have #{labels.to_sentence}. The allocation formulas read " \
                                        "#{labels.size == 1 ? 'it' : 'them'} to pick each folio's share; a blank value does not raise an error, " \
                                        "it allocates nothing to any folio.",
                           helper: "required_custom_fields", args: "#{target.inspect}, #{labels.inspect}#{options}",
                           evidence: readers.flat_map { |key, ffs| formula_evidence(ffs, "reads json_fields['#{key}']") })
        end
      end

      # Entry types allocated by entry type whose uploads have been mapped to a portfolio investment
      def deal_mapping
        mapped = context.uploaded.select { |u| u[:parent_type] == "PortfolioInvestment" }.to_set { |u| u[:entry_type] }
        pairs = entry_type_allocations.select { |pair| mapped.include?(pair.first) }
        return [] if pairs.empty?

        types = pairs.map(&:first).sort
        [Suggestion.build(key: "rule:deal_mapping", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                          name: "Pre-run check: Deal entries mapped to a portfolio investment",
                          description: "Uploaded #{types.to_sentence} entries must be mapped to one of this fund's portfolio investments. " \
                                       "They are reported per investment; an entry left unmapped, or mapped only to the company, " \
                                       "is missing from the investment's figures in the investor statement.",
                          helper: "entries_mapped_to_portfolio_investment", args: types.inspect,
                          evidence: formula_evidence(pairs.flat_map(&:last), "allocates by entry type") +
                                    [fact("Past uploads of #{types.to_sentence} were mapped to portfolio investments")])]
      end

      # A field on the allocated entry or investment that names the folio field holding each folio's share
      def folio_shares
        readers = Hash.new { |h, k| h[k] = [] }
        context.formulas.select { |ff| (ENTRY_ALLOCATION_TYPES + PORTFOLIO_ALLOCATION_TYPES).include?(ff.rule_type) }.each do |ff|
          text = ff.formula.to_s
          next unless text.match?(FOLIO_FIELD_READ)

          (text.scan(ENTRY_FIELD) + text.scan(INVESTMENT_FIELD)).flatten.uniq.each { |key| readers[key] << ff }
        end
        readers.keys.sort.map do |key|
          label = custom_field_label("AccountEntry", key)
          Suggestion.build(key: "rule:folio_shares:#{key}", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                           name: "Pre-run check: #{label} shares total 100%",
                           description: "Each #{label} used this period maps to a folio field holding each folio's " \
                                        "percentage, and those percentages must add up to 100. A code with no folio field, or with shares " \
                                        "that do not add up, allocates part of the amount to nobody, without any error.",
                           helper: "folio_shares_total", args: key.to_sym.inspect,
                           evidence: formula_evidence(readers[key], "reads json_fields['#{key}'] and the folio's share from capital_commitment.json_fields"))
        end
      end

      # Keys the formulas read off a folio's unit setting: json fields and columns
      def unit_settings
        readers = Hash.new { |h, k| h[k] = [] }
        columns = context.unit_setting_columns - %w[id json_fields fund_id entity_id name created_at updated_at]
        context.formulas.each do |ff|
          text = ff.formula.to_s
          keys = text.scan(UNIT_SETTING_JSON).flatten + text.scan(UNIT_SETTING_CALL).flatten.select { |c| columns.include?(c) }
          keys.uniq.each { |key| readers[key] << ff }
        end
        return [] if readers.empty?

        keys = readers.keys.sort
        evidence = readers.flat_map { |key, ffs| formula_evidence(ffs, "reads the unit setting's #{key}") }
        evidence << fact("Unit types in use: #{context.unit_types.map { |type, n| "#{type.presence || '(blank)'} (#{n})" }.join(', ')}")
        [Suggestion.build(key: "rule:unit_settings", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                          name: "Pre-run check: Unit settings for every unit type",
                          description: "Every unit type in use must have a unit setting with #{keys.to_sentence}. The formulas read them " \
                                       "from the folio's unit setting; a unit type with no setting stops the run part-way with " \
                                       "\"undefined method for nil\".",
                          helper: "unit_settings_present", args: keys.inspect, evidence:)]
      end

      def fx_rates
        sources = context.fx_rate_sources
        return [] if sources.empty?

        [Suggestion.build(key: "rule:fx_rates", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                          name: "Pre-run check: FX rates up to the end date",
                          description: "Every exchange rate the fund needs must be dated within 5 days before the run's end date. " \
                                       "Without it, amounts in the tracking or fund currency are converted at a stale rate.",
                          helper: "fx_rates_present", args: "within_days: 5",
                          evidence: sources.map { |(from, to), needed_by| fact("#{from} to #{to}, needed by #{needed_by.to_sentence}") })]
      end

      def valuations
        return [] unless context.portfolio_investments?

        [Suggestion.build(key: "rule:valuations", source: "rule", rule_type: FundFormula::PRE_RUN_CHECK,
                          name: "Pre-run check: Portfolio valuations up to the end date",
                          description: "Every portfolio company the fund holds should have a valuation within 3 months before the run's end " \
                                       "date. A warning, not a failure: a stale valuation makes FMV out of date, not the allocation wrong.",
                          helper: "valuations_present", args: "within_months: 3", severity: "warning",
                          evidence: [fact("The fund holds portfolio investments")])]
      end

      # --- Post-run ------------------------------------------------------------------------------------

      def entries_allocated
        allocating = context.formulas.select { |ff| ENTRY_ALLOCATION_TYPES.include?(ff.rule_type) }
        return [] if allocating.empty?

        evidence = formula_evidence(allocating, "allocates fund-level entries")
        [Suggestion.build(key: "rule:entries_allocated", source: "rule", rule_type: FundFormula::POST_RUN_CHECK,
                          name: "Post-run check: Fund level entries allocated",
                          description: "Every entry uploaded at fund level must be picked up by one of the fund's entry allocation formulas. " \
                                       "An entry no formula picks up never reaches the folios.",
                          helper: "fund_entries_allocated", args: "", evidence:),
         Suggestion.build(key: "rule:entries_tie", source: "rule", rule_type: FundFormula::POST_RUN_CHECK,
                          name: "Post-run check: Fund level entries tie to folios",
                          description: "The fund-level totals each allocation formula picked up must equal what it wrote to the folios, " \
                                       "within 1.00. A difference means part of an entry was not allocated.",
                          helper: "fund_entries_tie_to_folios", args: "tolerance: 1.0", evidence:)]
      end

      # Portfolio allocation formulas that allocate one investment amount column as it is
      def portfolio_tie
        candidates = context.formulas.select { |ff| PORTFOLIO_ALLOCATION_TYPES.include?(ff.rule_type) }
        duplicate_names = candidates.map(&:name).tally.select { |_, n| n > 1 }.keys
        amount_columns = PortfolioInvestment.column_names
        pairs = []
        skipped = []
        candidates.each do |ff|
          text = ff.formula.to_s
          columns = text.scan(INVESTMENT_AMOUNT).flatten.uniq & amount_columns
          reason = if columns.size != 1 then nil
                   elsif duplicate_names.include?(ff.name) then "another portfolio allocation formula has the same name"
                   elsif text.match?(SIGN_FLIP) then "it changes the sign of #{columns.first}"
                   elsif text.match?(/get_account_entry|compute_\w+|account_entries/) then "it combines the column with other figures"
                   end
          next if columns.size != 1
          next skipped << [ff, reason] if reason

          pairs << [ff, columns.first]
        end
        return [] if pairs.empty?

        evidence = pairs.flat_map { |ff, column| formula_evidence([ff], "allocates portfolio_investment.#{column}") } +
                   skipped.flat_map { |ff, reason| formula_evidence([ff], "not compared: #{reason}") }
        [Suggestion.build(key: "rule:portfolio_tie", source: "rule", rule_type: FundFormula::POST_RUN_CHECK,
                          name: "Post-run check: Portfolio investments tie to folios",
                          description: "Each portfolio investment's amount must equal what #{pairs.size == 1 ? 'its allocation formula' : 'each allocation formula'} " \
                                       "wrote to the folios, within 1.00. Formulas that change the sign of the amount or combine it " \
                                       "with other figures are left out, as they cannot tie to the column.",
                          helper: "portfolio_allocations_tie", args: pairs.map { |ff, column| "#{ff.name.inspect} => :#{column}" }.join(", "),
                          evidence:)]
      end

      # Names with a formula named "Since Inception <name>" that totals that one name
      def since_inception
        formulas = context.formulas.select do |ff|
          (m = ff.formula.to_s.match(SINGLE_SINCE_INCEPTION)) && ff.name == "Since Inception #{m[1]}"
        end
        return [] if formulas.empty?

        names = formulas.map { |ff| ff.name.delete_prefix("Since Inception ") }.uniq.sort
        state = context.incremental? ? "This fund uses incremental allocation, which" : "Under incremental allocation a run"
        [Suggestion.build(key: "rule:since_inception", source: "rule", rule_type: FundFormula::POST_RUN_CHECK,
                          name: "Post-run check: Since Inception totals match history",
                          description: "Each folio's stored Since Inception total on the end date must equal the sum of all its entries of " \
                                       "that name up to the end date, within 1.00, for #{names.size} #{'name'.pluralize(names.size)}. " \
                                       "#{state} carries the stored total forward instead of summing history, so a wrong carried total shows up here.",
                          helper: "since_inception_matches_history", args: names.inspect,
                          evidence: formula_evidence(formulas, "stores the since-inception total"))]
      end

      # --- Helpers -------------------------------------------------------------------------------------

      # [[entry_type, [formulas]]] for entry allocation formulas that select by entry type, in sequence order
      def entry_type_allocations
        context.formulas.select { |ff| CheckHelpers::ENTRY_ALLOCATION_SELECTORS[ff.rule_type] == :entry_type && ff.entry_type.present? }
               .group_by(&:entry_type).to_a
      end

      def custom_field_label(model, key)
        label = context.custom_field_labels(model)[key]
        label.presence || key.titleize
      end

      def formula_evidence(formulas, detail)
        formulas.uniq.sort_by(&:sequence).first(MAX_EVIDENCE_FORMULAS)
                .map { |ff| { "formula_id" => ff.id, "sequence" => ff.sequence, "name" => ff.name, "detail" => detail } }
      end

      def fact(detail) = { "detail" => detail }
    end
  end
end
