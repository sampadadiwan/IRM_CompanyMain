module AccountEntryAllocation
  # Moves a fund onto incremental since_inception allocation — or back — in one step.
  # See docs/modules/allocation/incremental_allocation_history.md section 12, and lib/tasks/incremental_allocation.rake.
  #
  # Every operation is planned first, as a Plan (plain data), and written by apply! from that plan:
  #   enable_plan    the formula edits the fund needs, anything that blocks it (a history read no automatic
  #                  edit covers, a since_inception with no stored total to carry forward), and corrected
  #                  starting values for tracking formulas, computed from a full copy
  #   disable_plan   restore the formulas this migration edited from their audit trail — except tracking
  #                  formulas, whose fix is correct with or without the flag (reverting it on top of
  #                  corrected starting values would double count) — and turn the flag off
  #   describe_plan  add the description to formulas edited before descriptions were written
  #   reseed_plan    recompute tracking formulas' stored since-inception entries on a date from full history
  #
  # Callers:
  #   - the fund formula operations page (FundFormulaOperationJob) previews a plan, stores it, and later
  #     calls apply!(plan), which plans again and refuses if anything changed in between
  #   - lib/tasks/incremental_allocation.rake calls enable!/disable!/describe!/reseed!, which plan, print
  #     the plan with TextReport, and write it straight away when asked to
  #
  # Every edited formula also gets a description of what it computes and why it was changed: written
  # whole when the formula had none, appended to one it had.
  #
  # Pre/post-run check formulas are left out of every plan: they are evaluated against the primary
  # database, never the trimmed scratch copy, so none of the history-read rules apply to them.
  class IncrementalMigration
    include WithScratchSqlite

    AUDIT_COMMENT = "incremental allocation migration".freeze
    ROLLBACK_COMMENT = "incremental allocation rollback".freeze
    DESCRIBE_COMMENT = "incremental allocation description".freeze
    # Present in every description this migration writes, so it is never added twice
    DESCRIPTION_MARKER = "Changed by the incremental allocation migration".freeze

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

    OPERATIONS = %w[enable_incremental disable_incremental describe_incremental reseed_carry_forward].freeze

    # apply! found the fund changed since the plan was made: nothing was written
    class PlanChanged < StandardError; end
    # apply! was handed a plan that cannot be written (blocked, or nothing to do)
    class NotApplicable < StandardError; end

    attr_reader :fund

    def initialize(fund, out: $stdout)
      @fund = fund
      @out = out
    end

    def enabled?
      CommitmentAccountEntry.incremental_since_inception?(fund)
    end

    # --- Plans (read-only) ---------------------------------------------------------------------------

    # with_values: false skips the full copy, leaving tracking starting values uncomputed
    def enable_plan(with_values: true)
      base = { "operation" => "enable_incremental", "formula_count" => fund.fund_formulas.count }
      return Plan.new(base.merge("already_enabled" => true)) if enabled?

      @edits = []
      @blockers = []
      @warnings = []
      @reseeds = []
      planned_formulas.each { |ff| plan_formula(ff) }
      compute = with_values && @blockers.empty? && @reseeds.any?
      compute_reseed_values(@reseeds) if compute

      Plan.new(base.merge("flag" => true, "edits" => @edits, "blockers" => @blockers, "warnings" => @warnings,
                          "reseeds" => @reseeds, "values_computed" => compute,
                          "params" => { "with_values" => with_values }))
    end

    def disable_plan
      audits = migration_audits
      warnings = []
      edits = audits.filter_map do |formula_id, formula_audits|
        ff = FundFormula.find(formula_id)
        next if ff.formula.to_s.match?(OWN_CARRY) # tracking fix stays, and so does the description saying so

        # The text before this migration first touched the formula. The description likewise, but only while
        # it is still what the migration last wrote: one edited by hand since is kept, and said so.
        description_audits = formula_audits.select { |a| a.audited_changes.key?("description") }
        restore_description = description_audits.any? && ff.description.to_s == description_audits.last.audited_changes.dig("description", 1).to_s
        warnings << { "formula_id" => ff.id, "message" => "seq #{ff.sequence} #{ff.name}: description edited since the migration, left as it is" } if description_audits.any? && !restore_description
        edit_for(ff, formula_after: original_value(formula_audits, "formula") || ff.formula,
                     description_after: restore_description ? original_value(formula_audits, "description") : ff.description)
      end
      Plan.new("operation" => "disable_incremental", "formula_count" => fund.fund_formulas.count, "audited" => audits.any?,
               "flag" => false, "edits" => edits, "warnings" => warnings, "params" => { "enabled" => enabled? })
    end

    # The description for formulas this migration edited before it wrote descriptions. The kind of edit is
    # worked out again from the formula text the migration started from, in the audit trail.
    def describe_plan
      warnings = []
      edits = migration_audits.filter_map do |formula_id, formula_audits|
        ff = FundFormula.find(formula_id)
        next if ff.description.to_s.include?(DESCRIPTION_MARKER)

        before = original_value(formula_audits, "formula")
        pattern, = before && !multiple?(ff) ? rewrite(before) : nil
        unless pattern
          warnings << { "formula_id" => ff.id, "message" => "seq #{ff.sequence} #{ff.name}: cannot tell how it was edited, left as it is" }
          next
        end

        edit_for(ff, description_after: describe(ff, pattern, ff.formula.to_s, before))
      end
      Plan.new("operation" => "describe_incremental", "formula_count" => fund.fund_formulas.count,
               "audited" => true, "edits" => edits, "warnings" => warnings)
    end

    # formulas: defaults to the fund's tracking formulas. date: defaults, per formula, to the latest date it
    # stored a folio entry; a formula with nothing stored is reported and left alone.
    def reseed_plan(formulas: nil, date: nil)
      formulas ||= planned_formulas.select { |ff| ff.formula.to_s.match?(OWN_CARRY) }
      warnings = []
      reseeds = formulas.filter_map do |ff|
        on = date || latest_stored_date(ff)
        unless on
          warnings << { "formula_id" => ff.id, "message" => "seq #{ff.sequence} #{ff.name}: no stored entries, nothing to recompute" }
          next
        end

        reseed_for(ff, ff.formula.to_s, on)
      end
      compute_reseed_values(reseeds) if reseeds.any?
      Plan.new("operation" => "reseed_carry_forward", "formula_count" => fund.fund_formulas.count, "reseeds" => reseeds,
               "warnings" => warnings, "values_computed" => reseeds.any?,
               "params" => { "formula_ids" => formulas.map(&:id), "date" => date&.iso8601 })
    end

    # Builds the plan for an operation from its stored params, as the preview did
    def plan_for(operation, params = {})
      params = params.to_h.stringify_keys
      case operation
      when "enable_incremental" then enable_plan(with_values: params.fetch("with_values", true))
      when "disable_incremental" then disable_plan
      when "describe_incremental" then describe_plan
      when "reseed_carry_forward"
        formulas = params["formula_ids"].presence&.then { |ids| fund.fund_formulas.where(id: ids).order(:sequence).to_a }
        reseed_plan(formulas:, date: params["date"].presence&.then { |d| Date.parse(d) })
      else raise ArgumentError, "unknown operation #{operation.inspect}"
      end
    end

    # --- Writing -------------------------------------------------------------------------------------

    # Writes a previewed plan after planning again: refuses (PlanChanged) if the formulas, descriptions,
    # audit trail, stored starting values or recomputed totals differ from the preview.
    # @return [Hash] what was written
    def apply!(plan)
      fresh = plan_for(plan.operation, plan.params)
      raise PlanChanged, "The fund has changed since this preview was made. Preview it again." if fresh.fingerprint != plan.fingerprint

      write!(fresh)
    end

    # --- Rake entry points: plan, print, write when asked ---------------------------------------------

    # apply: false only reports (including the corrected starting values, which are read-only to compute)
    def enable!(apply:)
      report = TextReport.new(fund, @out)
      plan = enable_plan(with_values: false)
      report.enable(plan)
      return :already_enabled if plan.already_enabled?
      return :blocked if plan.blocked?

      if plan.reseeds.any?
        report.loading_full_copy
        plan = enable_plan(with_values: true)
        report.reseed_values(plan)
      end
      return :dry_run unless apply

      write!(plan)
      report.enabled(plan)
      :enabled
    end

    def disable!(apply:)
      report = TextReport.new(fund, @out)
      plan = disable_plan
      report.disable(plan)
      return :dry_run unless apply

      write!(plan)
      report.disabled(plan)
      :disabled
    end

    def describe!(apply:)
      report = TextReport.new(fund, @out)
      plan = describe_plan
      report.describe(plan)
      return :dry_run unless apply

      write!(plan)
      report.described(plan)
      :described
    end

    # The rake reseed_carry_forward task: explicit formulas and date
    def reseed!(formulas:, date:, apply:)
      report = TextReport.new(fund, @out)
      report.loading_full_copy
      plan = reseed_plan(formulas:, date:)
      written = apply ? write!(plan)["starting_values"] : 0
      report.reseed(plan, applied: apply, updated: written)
      apply ? :reseeded : :dry_run
    end

    # --- Full copy -----------------------------------------------------------------------------------

    # A full scratch copy of the fund (never trimmed), for evaluating formulas over all history
    def with_full_copy(&)
      db = ActiveRecord::Base.connection_db_config.configuration_hash
      path = Rails.root.join("tmp/allocation/migration_#{fund.id}_#{Process.pid}.sqlite3").to_s
      FileUtils.mkdir_p(File.dirname(path))
      env = { "FUND_IDS" => fund.id.to_s, "SQLITE_DB" => path, "SCRATCH_DIR" => File.dirname(path), "ADAPTER" => db[:adapter].to_s,
              "MYSQL_HOST" => db[:host].to_s, "MYSQL_PORT" => db[:port].to_s, "MYSQL_USER" => db[:username].to_s,
              "MYSQL_PASS" => db[:password].to_s, "MYSQL_DB" => db[:database].to_s }
      env["SOURCE_SQLITE_DB"] = Rails.root.join(db[:database]).to_s if db[:adapter].to_s == "sqlite3"
      Rails.logger.info { "IncrementalMigration: loading a full copy of fund #{fund.id}" }
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

    private

    def planned_formulas
      fund.fund_formulas.without_run_checks.order(:sequence).to_a
    end

    # One transaction: formula edits (validated, audited), stored starting values, the flag
    def write!(plan)
      raise NotApplicable, "Nothing to apply: the fund is already on incremental allocation" if plan.already_enabled?
      raise NotApplicable, "Blocked: #{plan.blockers.size} issue(s) need a manual formula edit" if plan.blocked?
      raise NotApplicable, "Starting values were not computed for this plan" if plan.reseeds.any? && !plan.values_computed?

      comment = { "enable_incremental" => AUDIT_COMMENT, "disable_incremental" => ROLLBACK_COMMENT,
                  "describe_incremental" => DESCRIBE_COMMENT }[plan.operation]
      written = { "formulas" => 0, "starting_values" => 0, "flag" => plan.flag }
      ActiveRecord::Base.transaction do
        plan.edits.each do |edit|
          attrs = {}
          attrs[:formula] = edit["formula_after"] if edit["formula_after"] != edit["formula_before"]
          attrs[:description] = edit["description_after"] if edit["description_after"] != edit["description_before"]
          next if attrs.empty?

          fund.fund_formulas.find(edit["formula_id"]).update!(**attrs, audit_comment: comment)
          written["formulas"] += 1
        end
        plan.reseeds.each { |reseed| written["starting_values"] += write_reseed(reseed) }
        set_flag(plan.flag) unless plan.flag.nil?
      end
      written
    end

    def edit_for(fund_formula, formula_after: fund_formula.formula, description_after: fund_formula.description, pattern: nil)
      { "formula_id" => fund_formula.id, "sequence" => fund_formula.sequence, "name" => fund_formula.name, "pattern" => pattern&.to_s,
        "formula_before" => fund_formula.formula, "formula_after" => formula_after,
        "description_before" => fund_formula.description, "description_after" => description_after }
    end

    def reseed_for(fund_formula, formula, date)
      { "formula_id" => fund_formula.id, "sequence" => fund_formula.sequence, "name" => fund_formula.name,
        "formula" => formula, "date" => date.iso8601, "values" => [] }
    end

    def latest_stored_date(fund_formula)
      fund.account_entries.where(fund_formula_id: fund_formula.id, cumulative: false, generated: true, deleted_at: nil)
          .where.not(capital_commitment_id: nil).maximum(:reporting_date)
    end

    # Fills each reseed's values: the recomputed total per commitment, and the amount stored today (nil
    # where nothing is stored, which apply leaves alone)
    def compute_reseed_values(reseeds)
      with_full_copy do
        reseeds.each do |reseed|
          fund_formula = fund.fund_formulas.find(reseed["formula_id"])
          date = Date.parse(reseed["date"])
          stored = stored_amounts(fund_formula, date)
          reseed["values"] = since_inception_totals(fund_formula, reseed["formula"], date).map do |cc_id, total|
            { "capital_commitment_id" => cc_id, "old_cents" => stored[cc_id]&.then { |a| cents(a) }, "new_cents" => cents(total) }
          end
        end
      end
    end

    # {capital_commitment_id => amount_cents} for the formula's stored folio entries on date, in one query
    def stored_amounts(fund_formula, date)
      stored_entries(fund_formula.id, date).pluck(:capital_commitment_id, :amount_cents).to_h
    end

    def stored_entries(fund_formula_id, date)
      AccountEntry.where(fund_id: fund.id, fund_formula_id:, reporting_date: date, cumulative: false, generated: true, deleted_at: nil)
    end

    # Same columns the engine fills for these entries: folio amount equals amount, and the tracking
    # amount is the amount at the date's rate (what TrackingCurrencyJob writes). Only stored entries are
    # overwritten; none are created.
    # @return [Integer] entries written
    def write_reseed(reseed)
      date = Date.parse(reseed["date"])
      ids = stored_entries(reseed["formula_id"], date).pluck(:capital_commitment_id, :id).to_h
      rate = nil
      reseed["values"].sum do |value|
        id = ids[value["capital_commitment_id"]]
        next 0 unless id && value["old_cents"]

        # Looked up once, and only when there is an entry to write: a tracking-currency fund with no rate on
        # the date must still be able to apply a plan that writes nothing
        rate ||= fund.tracking_currency.present? ? fund.tracking_exchange_rate(exchange_rate_date: date).rate : 1
        total = BigDecimal(value["new_cents"])
        # Keyed on the composite primary key; the same columns the engine writes for these entries
        AccountEntry.where(id:, reporting_date: date).update_all(amount_cents: total, folio_amount_cents: total, tracking_amount_cents: total * rate)
        1
      end
    end

    # A formula that evaluates to nil for a commitment counts as zero, as its stored entry would
    def cents(value)
      BigDecimal(value.to_s.presence || "0").to_s("F")
    end

    def set_flag(value)
      # update_column: json_fields only, without the fund's save callbacks
      fund.update_column(:json_fields, fund.json_fields.to_h.merge("incremental_since_inception" => value))
    end

    def plan_formula(fund_formula)
      text = fund_formula.formula.to_s
      label = "seq #{fund_formula.sequence} #{fund_formula.name}"
      # GenerateAccountEntryMultiple expands its names array into one evaluation per name, each carrying
      # forward "Since Inception <name>" — never rewrite those to carry the formula's own name
      pattern, new_text = multiple?(fund_formula) ? [nil, text] : rewrite(text)
      if pattern
        @edits << edit_for(fund_formula, pattern:, formula_after: new_text,
                                         description_after: describe(fund_formula, pattern, new_text, text))
      end

      block = ->(message) { @blockers << { "formula_id" => fund_formula.id, "message" => "#{label}: #{message}" } }
      # Anything that still reads history the trimmed copy does not hold
      block.call("reads a date range with no start (not a latest-row lookup)") if new_text.match?(BEGINLESS_READ)
      block.call("total_amount without start_date") if open_total_amounts(new_text).any?
      block.call("compares reporting_date inside a SQL string") if new_text.match?(/["'][^"']*reporting_date\s*[<>=]/)
      block.call("reads account entries with no date filter") if undated_read?(new_text)
      uncovered_dates(new_text).each { |kind, date| block.call("#{kind} from '#{date}', which may be before the trimmed copy starts") }
      carry_names(fund_formula, new_text).each do |name|
        block.call("no stored '#{name}' to carry forward") if stored_named(name).none?
      end

      return unless pattern == :tracking

      latest = latest_stored_date(fund_formula)
      if latest
        @reseeds << reseed_for(fund_formula, new_text, latest)
      else
        @warnings << { "formula_id" => fund_formula.id,
                       "message" => "#{label}: tracking formula has never produced a figure#{' (disabled)' unless fund_formula.enabled}; " \
                                    "seed its starting value (rake allocation:reseed_carry_forward) before relying on it" }
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

    # The description an edited formula gets: what it computes and why the migration changed it. A
    # formula with no description gets all of it; an existing description is kept and the rest appended.
    # before is the text the migration started from, new_text what it wrote.
    def describe(fund_formula, pattern, new_text, before)
      existing = fund_formula.description.to_s.strip
      return existing if existing.include?(DESCRIPTION_MARKER)

      what, how, why = case pattern
                       when :tracking then describe_tracking(fund_formula, new_text)
                       when :combined then describe_combined(fund_formula, before)
                       when :feeder then describe_feeder(fund_formula, before)
                       end

      skip = new_text.include?("SkipRule") && new_text.include?("feeder_fund_id") ? " Folios that belong to a feeder fund are skipped." : ""
      change = "#{how}#{skip}\n\n#{DESCRIPTION_MARKER} (rake allocation:enable_incremental): #{why}"
      existing.empty? ? "#{what}\n\n#{change}" : "#{existing}\n\n#{change}"
    end

    def describe_tracking(fund_formula, new_text)
      sums = new_text.scan(/account_entries\.(for_parent_account_entries|for_portfolio_investments)(.*?)\.sum\(:\w+\)/m).map do |source, chain|
        from = source == "for_parent_account_entries" ? "allocated from this fund's fund-level account entries" : "linked to this fund's portfolio investments"
        filters = chain.scan(/\b(name|entry_type):\s*(\[[^\]]*\]|"[^"]*"|account_entry_name)/).map do |field, value|
          values = value == "account_entry_name" ? [fund_formula.name.sub(" tracking", "").strip] : value.scan(/"([^"]+)"/).flatten
          label = field == "name" ? "named" : "of entry #{'type'.pluralize(values.size)}"
          "#{label} #{values.map { |v| %("#{v}") }.to_sentence}"
        end
        "the folio's entries #{from}#{" #{filters.join(', ')}" if filters.any?}"
      end
      currency = new_text.include?("tracking_amount_cents") ? ", in the fund's tracking currency," : ""
      what = "The since-inception total#{currency} of #{sums.presence&.join(', plus ') || "the folio's entries"}."
      how = "How it is computed: the latest value this formula stored on or before the run's start date (the previous run's " \
            "since-inception total), plus the entries dated inside the run, from the start date to the end date."
      why = "the sum used to run from inception (reporting_date: ..@end_date) while still adding the stored value, so every run " \
            "re-added all history and the stored total grew with the number of runs rather than with the data. The sum is now " \
            "limited to the run's dates. This needs a correct stored starting value: rake allocation:reseed_carry_forward " \
            "recomputes it from full history."
      [what, how, why]
    end

    def describe_combined(fund_formula, before)
      names = before.scan(SINGLE_SI).flatten
      what = "The folio's since-inception total of #{names.map { |n| %("#{n}") }.to_sentence}."
      why = "it summed #{names.size} separate since_inception calls, each of which would carry forward its own " \
            "\"Since Inception <name>\" total, and those totals are never stored. They are now one call over all " \
            "#{names.size} names that carries forward this formula's own total (carry_forward_name)."
      [what, carry_forward_how(fund_formula), why]
    end

    def describe_feeder(fund_formula, before)
      # Read from the original: the rewritten call no longer ends where ARRAY_SI expects
      names = before[ARRAY_SI, 1].to_s[/\[([^\]]*)\]/, 1].to_s.scan(/"([^"]+)"/).flatten
      bounded = open_total_amounts(before).map { |m| m.scan(/name:\s*\[([^\]]*)\]/).flatten.join(",").scan(/"([^"]+)"/).flatten }
      less = bounded.flatten.presence&.then { |n| ", less the folio's portfolio entries named #{n.map { |v| %("#{v}") }.to_sentence} (total_amount)" }
      what = "The folio's since-inception total of #{names.map { |n| %("#{n}") }.to_sentence}#{less}."
      bounded_note = ", and total_amount is now summed from the run start date (start_date: @start_date) rather than from inception"
      why = "the names array summed all history; it now carries forward this formula's own total (carry_forward_name)#{bounded_note if bounded.any?}."
      [what, carry_forward_how(fund_formula), why]
    end

    def carry_forward_how(fund_formula)
      "How it is computed: the latest \"#{fund_formula.name}\" total this formula stored before the run's start date, " \
        "plus the movement in those entries since that date. On a folio's first run, or when the fund is regenerated " \
        "from inception, there is no stored total and it is the sum of all history. A run fails rather than read zero " \
        "when an older folio has history but no stored total. Funds not switched to incremental allocation still sum all history."
    end

    # The migration's audits for this fund's formulas since it was last switched off, oldest first, grouped
    # by formula id. A switch-off restores a formula and writes a rollback audit; anything the migration
    # wrote before that rollback has already been undone, so "the value before the migration" is the value
    # before its first edit *after* the rollback — otherwise a second switch-off would discard whatever was
    # edited by hand between the two cycles.
    def migration_audits
      Audited::Audit.where(auditable_type: "FundFormula", auditable_id: fund.fund_formulas.select(:id),
                           comment: [AUDIT_COMMENT, DESCRIBE_COMMENT, ROLLBACK_COMMENT])
                    .order(:created_at, :id).group_by(&:auditable_id)
                    .transform_values { |audits| audits.reverse.take_while { |a| a.comment != ROLLBACK_COMMENT }.reverse }
                    .reject { |_, audits| audits.empty? }
    end

    # A column's value before the first of these audits changed it (nil if none did)
    def original_value(formula_audits, column)
      formula_audits.find { |a| a.audited_changes.key?(column) }&.audited_changes&.dig(column, 0)
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
          @blockers << { "formula_id" => fund_formula.id, "message" => "seq #{fund_formula.sequence} #{fund_formula.name}: custom name_prefix, carry-forward cannot find its stored totals" } if fund_formula.multiple_entry_prefixed_names != expected
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
  end
end
