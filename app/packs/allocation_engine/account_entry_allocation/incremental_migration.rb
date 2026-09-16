module AccountEntryAllocation
  # Moves a fund onto incremental since_inception allocation — or back — in one step.
  # See docs/modules/allocation/incremental_allocation_history.md section 12, and lib/tasks/incremental_allocation.rake.
  #
  # enable:
  #   1. plan: find the formula edits the fund needs, and anything that blocks it (a history read no
  #      automatic edit covers, a since_inception with no stored total to carry forward)
  #   2. compute corrected starting values for active tracking formulas, in memory, from a full copy
  #   3. one transaction: formula edits (validated, audited), corrected starting values, the flag
  # A blocked fund is reported and left untouched.
  #
  # disable: flag off, and restore the formulas this migration edited from their audit trail — except
  # tracking formulas, whose fix is correct with or without the flag (reverting it on top of corrected
  # starting values would double count).
  class IncrementalMigration
    include WithScratchSqlite

    AUDIT_COMMENT = "incremental allocation migration".freeze
    ROLLBACK_COMMENT = "incremental allocation rollback".freeze

    # "..@end_date" range not followed by ".order(...).last": a sum over all history, not a latest-row lookup
    OPEN_SUM = /reporting_date:\s*\.\.\s*@end_date\)(?!\s*\.order\([^)]*\)\s*\.last)/
    # The formula adding its own previous stored value
    OWN_CARRY = /get_account_entry_or_zero\(\s*fund_formula\.name\s*,\s*@start_date\s*\)/
    SINGLE_SI = /capital_commitment\.since_inception\("([^"]+)",\s*nil,\s*@start_date,\s*@end_date\)/
    ARRAY_SI = /(since_inception\(\s*\[[^\]]*\]\s*,\s*nil\s*,\s*@start_date\s*,\s*@end_date)\s*\)/
    TOTAL_AMOUNT = /total_amount\((?:[^()]|\([^()]*\))*\)/m
    # Helpers that bound their own date range, so a formula using them is not an undated read
    DATED_HELPERS = /since_inception|year_to_date|quarterly|period\(|on_date|get_account_entry|cumulative_account_entry|total_amount/
    # Dates the trimmed copy covers from: it keeps everything from min(financial-year start, quarter start,
    # start_date). A history read from any other date — an expression, a local variable, a date from the
    # data — may reach before that and silently read less.
    COVERED_DATE = /\A@(start_date|end_date|end_date\.beginning_of_quarter|start_of_financial_year)\z/
    # Beginless range not used as a latest-row lookup
    BEGINLESS_READ = /reporting_date:\s*\.\.\s*[^,)\s]+\)(?!\s*\.order\([^)]*\)\s*\.last)/
    RANGE_START = /reporting_date:\s*([^.,)\s][^,)]*?)\s*\.\./
    AS_OF_DATE = /(?:get_account_entry(?:_or_zero)?|get_ic_account_entry)\(\s*(?:"[^"]*"|[\w.@]+)\s*,\s*([^,)]+)/
    ON_DATE = /\b(?:as_)?on_date\(\s*[^,]+,\s*[^,]+,\s*([^,)]+)/
    START_DATE_ARG = /start_date:\s*([^,)]+)/
    FAR_PAST = Date.new(1900, 1, 1)

    Edit = Struct.new(:fund_formula, :pattern, :formula, keyword_init: true)
    Reseed = Struct.new(:fund_formula, :formula, :date, :totals, keyword_init: true)

    attr_reader :fund, :edits, :blockers, :warnings, :reseeds

    def initialize(fund, out: $stdout)
      @fund = fund
      @out = out
    end

    def enabled?
      CommitmentAccountEntry.incremental_since_inception?(fund)
    end

    # Read-only: what enabling would do
    def plan
      @edits = []
      @blockers = []
      @warnings = []
      @reseeds = []
      fund.fund_formulas.order(:sequence).each { |ff| plan_formula(ff) }
      self
    end

    # apply: false only reports (including the corrected starting values, which are read-only to compute)
    def enable!(apply:)
      if enabled?
        say "already enabled, nothing to do"
        return :already_enabled
      end

      plan
      report_plan
      if blockers.any?
        say "BLOCKED: #{blockers.size} issue(s) above need a manual formula edit. Nothing changed."
        return :blocked
      end

      compute_reseeds if reseeds.any?
      return :dry_run unless apply

      ActiveRecord::Base.transaction do
        edits.each { |e| e.fund_formula.update!(formula: e.formula, audit_comment: AUDIT_COMMENT) }
        reseeds.each { |r| write_reseed(r) }
        set_flag(true)
      end
      say "ENABLED: #{edits.size} formula edit(s), #{reseeds.sum { |r| r.totals.size }} starting value(s) corrected, flag on"
      :enabled
    end

    def disable!(apply:)
      audits = Audited::Audit.where(auditable_type: "FundFormula", auditable_id: fund.fund_formulas.select(:id), comment: AUDIT_COMMENT)
                             .order(:created_at).group_by(&:auditable_id)
      restores = audits.filter_map do |formula_id, formula_audits|
        ff = FundFormula.find(formula_id)
        next if ff.formula.to_s.match?(OWN_CARRY) # tracking fix stays

        # The text before this migration first touched the formula
        [ff, formula_audits.first.audited_changes["formula"]&.first]
      end

      say "flag #{enabled? ? 'on' : 'already off'}; #{restores.size} formula(s) to restore from the audit trail"
      restores.each { |ff, text| say "  seq #{ff.sequence} #{ff.name}\n    restore: #{text.to_s.squish.truncate(300)}" }
      say "  (tracking formula fixes are kept: they are correct with or without the flag)" if audits.any?
      say "  WARNING: no migration audit found for this fund's formulas; edited formulas are left as they are" if audits.empty?
      return :dry_run unless apply

      ActiveRecord::Base.transaction do
        restores.each { |ff, text| ff.update!(formula: text, audit_comment: ROLLBACK_COMMENT) if text }
        set_flag(false)
      end
      say "DISABLED: #{restores.size} formula(s) restored, flag off"
      :disabled
    end

    # A full scratch copy of the fund (never trimmed), for evaluating formulas over all history
    def with_full_copy(&)
      db = ActiveRecord::Base.connection_db_config.configuration_hash
      path = Rails.root.join("tmp/allocation/migration_#{fund.id}_#{Process.pid}.sqlite3").to_s
      FileUtils.mkdir_p(File.dirname(path))
      env = { "FUND_IDS" => fund.id.to_s, "SQLITE_DB" => path, "SCRATCH_DIR" => File.dirname(path), "ADAPTER" => db[:adapter].to_s,
              "MYSQL_HOST" => db[:host].to_s, "MYSQL_PORT" => db[:port].to_s, "MYSQL_USER" => db[:username].to_s,
              "MYSQL_PASS" => db[:password].to_s, "MYSQL_DB" => db[:database].to_s }
      env["SOURCE_SQLITE_DB"] = Rails.root.join(db[:database]).to_s if db[:adapter].to_s == "sqlite3"
      say "loading a full copy of fund #{fund.id} to compute starting values..."
      output, status = Open3.capture2e(env, "bash #{Rails.root.join('script/load_sqlite3_from_mysql.sh')}")
      raise "Loading fund #{fund.id} failed:\n#{output.lines.last(20).join}" unless status.success?

      with_scratch_sqlite(path, &)
    ensure
      WithScratchSqlite.disconnect_pool(path) if path
      FileUtils.rm_f([path, "#{path}-wal", "#{path}-shm", "#{path}-journal"].compact) if path
    end

    # The formula's since-inception value on date for each commitment: evaluated with @start_date far in
    # the past, its window covers all history and its own previous value reads zero.
    def since_inception_totals(fund_formula, formula, date)
      CapitalCommitmentSqlite.where(fund_id: fund.id, commitment_date: ..date).each_with_object({}) do |capital_commitment, totals|
        scope = Object.new
        scope.instance_variable_set(:@fund, fund)
        scope.instance_variable_set(:@start_date, FAR_PAST)
        scope.instance_variable_set(:@end_date, date)
        bdg = scope.instance_eval { binding }
        bdg.local_variable_set(:capital_commitment, capital_commitment)
        bdg.local_variable_set(:fund_formula, fund_formula)
        totals[capital_commitment.id] = bdg.eval(ApplicationRecord.safe_eval!(formula, context: "IncrementalMigration"))
      rescue SkipRule
        next
      end
    end

    def stored_entry(fund_formula, capital_commitment_id, date)
      AccountEntry.find_by(fund_id: fund.id, fund_formula_id: fund_formula.id, capital_commitment_id:, reporting_date: date,
                           cumulative: false, generated: true, deleted_at: nil)
    end

    # Same columns the engine fills for these entries: folio amount equals amount, and the tracking
    # amount is the amount at the date's rate (what TrackingCurrencyJob writes)
    def write_stored_total(entry, total)
      rate = fund.tracking_currency.present? ? fund.tracking_exchange_rate(exchange_rate_date: entry.reporting_date).rate : 1
      entry.update_columns(amount_cents: total, folio_amount_cents: total, tracking_amount_cents: total.to_d * rate)
    end

    private

    def say(message)
      @out.puts("[fund #{fund.id}] #{message}")
    end

    def plan_formula(fund_formula)
      text = fund_formula.formula.to_s
      label = "seq #{fund_formula.sequence} #{fund_formula.name}"
      # GenerateAccountEntryMultiple expands its names array into one evaluation per name, each carrying
      # forward "Since Inception <name>" — never rewrite those to carry the formula's own name
      pattern, new_text = multiple?(fund_formula) ? [nil, text] : rewrite(text)
      @edits << Edit.new(fund_formula:, pattern:, formula: new_text) if pattern

      # Anything that still reads history the trimmed copy does not hold
      @blockers << "#{label}: reads a date range with no start (not a latest-row lookup)" if new_text.match?(BEGINLESS_READ)
      @blockers << "#{label}: total_amount without start_date" if open_total_amounts(new_text).any?
      @blockers << "#{label}: compares reporting_date inside a SQL string" if new_text.match?(/["'][^"']*reporting_date\s*[<>=]/)
      @blockers << "#{label}: reads account entries with no date filter" if undated_read?(new_text)
      uncovered_dates(new_text).each { |kind, date| @blockers << "#{label}: #{kind} from '#{date}', which may be before the trimmed copy starts" }
      carry_names(fund_formula, new_text).each do |name|
        @blockers << "#{label}: no stored '#{name}' to carry forward" if stored_named(name).none?
      end

      return unless pattern == :tracking

      latest = fund.account_entries.where(fund_formula_id: fund_formula.id, cumulative: false, generated: true, deleted_at: nil)
                   .where.not(capital_commitment_id: nil).maximum(:reporting_date)
      if latest
        @reseeds << Reseed.new(fund_formula:, formula: new_text, date: latest)
      else
        @warnings << "#{label}: tracking formula has never produced a figure#{' (disabled)' unless fund_formula.enabled}; " \
                     "seed its starting value (rake allocation:reseed_carry_forward) before relying on it"
      end
    end

    # The three shapes found on funds 316-321. Returns [pattern, new formula text].
    def rewrite(text)
      if text.match?(OPEN_SUM) && text.match?(OWN_CARRY)
        # A: "all history + my previous stored value" compounds; bound the history to the window
        [:tracking, text.gsub(OPEN_SUM, "reporting_date: @start_date..@end_date)")]
      elsif text.strip.match?(/\A#{SINGLE_SI}(\s*\+\s*#{SINGLE_SI})+\s*\z/o)
        # B: several single-name totals added up; only the combined total is ever stored
        names = text.scan(SINGLE_SI).flatten
        [:combined, "capital_commitment.since_inception(#{names.to_json},nil,@start_date,@end_date, carry_forward_name: fund_formula.name)"]
      elsif text.match?(ARRAY_SI) && text.exclude?("carry_forward_name")
        # C: names array (optionally minus an open-ended total_amount); carry forward the formula's own total
        new_text = text.sub(ARRAY_SI, '\1, carry_forward_name: fund_formula.name)')
        open_total_amounts(new_text).each { |m| new_text = new_text.sub(m, m.sub("end_date:", "start_date: @start_date, end_date:")) }
        [:feeder, new_text]
      else
        [nil, text]
      end
    end

    def open_total_amounts(text)
      text.scan(TOTAL_AMOUNT).select { |m| m.include?("end_date:") && m.exclude?("start_date:") }
    end

    # [kind, date] for every history read that starts from a date the trimmed copy does not guarantee
    def uncovered_dates(text)
      reads = text.scan(RANGE_START).flatten.map { |d| ["date range", d] } +
              text.scan(AS_OF_DATE).flatten.map { |d| ["as-of lookup", d] } +
              text.scan(ON_DATE).flatten.map { |d| ["on_date", d] } +
              text.scan(START_DATE_ARG).flatten.map { |d| ["start_date:", d] }
      reads.map { |kind, date| [kind, date.strip] }.reject { |_, date| date.match?(COVERED_DATE) }.uniq
    end

    def undated_read?(text)
      text.match?(/account_entries|AccountEntry/) && !text.match?(/reporting_date|@start_date|@end_date/) && !text.match?(DATED_HELPERS)
    end

    def multiple?(fund_formula)
      fund_formula.rule_type == "GenerateAccountEntryMultiple"
    end

    # The stored totals since_inception will look for when this formula runs
    def carry_names(fund_formula, text)
      names = []
      # generate_ytd_qtly adds since_inception('<formula name>') for the formula (CreateAccountEntry)
      names << "Since Inception #{fund_formula.name}" if fund_formula.generate_ytd_qtly
      return names unless text.include?("since_inception")

      if multiple?(fund_formula)
        # One evaluation per name, each carrying forward "Since Inception <name>". A custom name_prefix
        # stores the totals under other names, which carry-forward cannot find.
        if text.match?(/since_inception\(\s*\[/)
          expected = fund_formula.multiple_entry_names.map { |n| "Since Inception #{n}" }
          @blockers << "seq #{fund_formula.sequence} #{fund_formula.name}: custom name_prefix, carry-forward cannot find its stored totals" if fund_formula.multiple_entry_prefixed_names != expected
          return names + expected
        end
      elsif text.include?("carry_forward_name")
        return names + [fund_formula.name]
      end

      # since_inception("Name", ...) or since_inception(nil, "Entry Type", ...)
      (names + text.scan(/since_inception\(\s*(?:"([^"]+)"|nil\s*,\s*"([^"]+)")/).map { |n, t| "Since Inception #{n || t}" }).uniq
    end

    def stored_named(name)
      fund.account_entries.where(name:, cumulative: false, deleted_at: nil).where.not(capital_commitment_id: nil)
    end

    def compute_reseeds
      with_full_copy do
        reseeds.each do |reseed|
          reseed.totals = since_inception_totals(reseed.fund_formula, reseed.formula, reseed.date)
          say "  starting values for seq #{reseed.fund_formula.sequence} #{reseed.fund_formula.name} on #{reseed.date}:"
          reseed.totals.each do |cc_id, total|
            entry = stored_entry(reseed.fund_formula, cc_id, reseed.date)
            say format("    commitment %<cc>d: %<old>s -> %<new>.2f", cc: cc_id, old: entry ? format("%.2f", entry.amount_cents / 100) : "no stored entry, skipped", new: total.to_d / 100)
          end
        end
      end
    end

    def write_reseed(reseed)
      reseed.totals.each do |cc_id, total|
        entry = stored_entry(reseed.fund_formula, cc_id, reseed.date)
        write_stored_total(entry, total) if entry
      end
    end

    def set_flag(value)
      # update_column: json_fields only, without the fund's save callbacks
      fund.update_column(:json_fields, fund.json_fields.to_h.merge("incremental_since_inception" => value))
    end

    def report_plan
      say "#{fund.name}: #{fund.fund_formulas.count} formulas"
      say "formula edits: #{edits.size}"
      edits.each do |e|
        say "  seq #{e.fund_formula.sequence} #{e.fund_formula.name} [#{e.pattern}]"
        say "    before: #{e.fund_formula.formula.to_s.squish.truncate(300)}"
        say "    after:  #{e.formula.squish.truncate(300)}"
      end
      say "starting values to correct: #{reseeds.map { |r| "seq #{r.fund_formula.sequence} on #{r.date}" }.join(', ').presence || 'none'}"
      warnings.each { |w| say "WARNING #{w}" }
      blockers.each { |b| say "BLOCKER #{b}" }
    end
  end
end
