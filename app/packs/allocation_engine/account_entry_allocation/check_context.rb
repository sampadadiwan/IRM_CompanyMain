module AccountEntryAllocation
  # The object a pre/post-run check formula is evaluated inside. A check runs once for the whole
  # fund, outside every allocation operation, so it deliberately sees only the fund-level values
  # below -- never a capital_commitment or another formula's output.
  #
  # Because the formula is evaluated against this object's binding, `check!`, `CheckFailed`,
  # `CheckWarning` and `SkipRule` all resolve by name inside a formula.
  class CheckContext
    include CheckHelpers

    # What a helper returns when it found nothing wrong: a pass with a summary worth showing,
    # e.g. "All 40 uploaded Non Deal Expense entries use an allowed name".
    Passed = Struct.new(:summary)

    def initialize(fund:, start_date:, end_date:, allocation_run:)
      @fund = fund
      @start_date = start_date
      @end_date = end_date
      @allocation_run = allocation_run
    end

    # Fails the check with message unless condition holds.
    #   check!(@fund.fund_unit_settings.exists?, "Fund has no unit settings")
    def check!(condition, message)
      raise CheckFailed, message unless condition

      true
    end

    # @param source [String] the formula text
    # @param label [String] identifies the formula in safe_eval!'s / FormulaSandbox's log line
    # @return [Object] whatever the formula's last expression evaluates to
    def evaluate(source, label:)
      # C2 — safe_eval! (every mode), then the run_check profile in log / enforce mode
      FormulaSandbox.evaluate(source, formula_binding, profile: "run_check", context: label, file: label, line: 1)
    end

    private

    # A binding taken from a method with no locals, so the formula cannot see (or clobber)
    # evaluate's own `source`/`label` variables.
    def formula_binding
      binding
    end
  end
end
