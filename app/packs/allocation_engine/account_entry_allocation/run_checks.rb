module AccountEntryAllocation
  # Runs every enabled pre-run or post-run check formula in scope for an allocation run and
  # returns one result per check. It never raises for a check's sake: a check that fails, warns,
  # skips or blows up is recorded, and the next check still runs, so a reviewer sees every
  # problem at once. Whether the run stops is RunFormulas' decision, made from the results.
  #
  # Each result is a string-keyed Hash, stored as-is in AllocationRunReport#json_fields["run_checks"]:
  #   "kind"        "pre" or "post"
  #   "formula_id", "sequence", "name"
  #   "result"      "pass", "warn", "fail" or "skipped"
  #   "summary"     one line, at most SUMMARY_LIMIT characters
  #   "columns", "rows", "filters", "truncated"  the rows behind a CheckFailed/CheckWarning
  #   "duration_ms"
  #
  # See docs/modules/allocation/allocation_run_checks.md.
  class RunChecks
    SUMMARY_LIMIT = 500
    KINDS = { pre: FundFormula::PRE_RUN_CHECK, post: FundFormula::POST_RUN_CHECK }.freeze

    # @param formulas [Enumerable<FundFormula>] the checks to run, in sequence order
    # @param kind [:pre, :post]
    def initialize(formulas, kind:, fund:, start_date:, end_date:, allocation_run:)
      @formulas = formulas
      @kind = kind
      @context_attrs = { fund:, start_date:, end_date:, allocation_run: }
    end

    # @return [Array<Hash>]
    def call
      @formulas.map { |formula| run_one(formula) }
    end

    private

    def run_one(formula)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = evaluate(formula)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      Rails.logger.info { "RunChecks: #{@kind} check #{formula.sequence} #{formula.name} -> #{outcome[:result]}: #{outcome[:summary]}" }

      rows = Array(outcome[:rows])
      limit = AllocationRunReport::MAX_ROWS_PER_FINDING
      {
        "kind" => @kind.to_s,
        "formula_id" => formula.id,
        "sequence" => formula.sequence,
        "name" => formula.name,
        "result" => outcome[:result],
        "summary" => outcome[:summary].to_s.truncate(SUMMARY_LIMIT),
        "columns" => Array(outcome[:columns]),
        "rows" => rows.first(limit),
        "filters" => Array(outcome[:filters]).first(limit),
        "truncated" => outcome[:truncated].to_i + [rows.size - limit, 0].max,
        "duration_ms" => duration_ms
      }
    end

    # rescue order matters: CheckWarning is a CheckFailed, and both are StandardErrors.
    def evaluate(formula)
      context = CheckContext.new(**@context_attrs)
      value = context.evaluate(formula.formula, label: "FundFormula##{formula.id}")
      # Only an explicit false fails. nil passes, so a formula ending in a logging call or an
      # `if` without an else does not fail by accident.
      return { result: "pass", summary: value.summary } if value.is_a?(CheckContext::Passed)

      value == false ? { result: "fail", summary: "Check returned false" } : { result: "pass", summary: "Passed" }
    rescue CheckWarning => e
      from_check_error("warn", e)
    rescue CheckFailed => e
      from_check_error("fail", e)
    rescue SkipRule => e
      { result: "skipped", summary: e.message.presence || "Skipped" }
    rescue StandardError, ScriptError => e
      # ScriptError covers a SyntaxError in a formula saved without validation (update_column,
      # imports). The class name is kept for anything but a bare `raise "message"`, so a typo
      # (NoMethodError, NameError) reads as a broken check rather than a failed assertion.
      Rails.logger.error { "RunChecks: #{@kind} check #{formula.id} raised #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}" }
      summary = e.instance_of?(RuntimeError) ? e.message : "#{e.class}: #{e.message}"
      { result: "fail", summary: }
    end

    def from_check_error(result, error)
      { result:, summary: error.message.presence || (result == "warn" ? "Check warned" : "Check failed"),
        columns: error.columns, rows: error.rows, filters: error.filters, truncated: error.truncated }
    end
  end
end
