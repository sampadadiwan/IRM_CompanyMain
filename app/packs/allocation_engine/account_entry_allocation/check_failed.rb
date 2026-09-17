module AccountEntryAllocation
  # Raised by a pre/post-run check (a FundFormula with rule type PreRunCheck or PostRunCheck) to
  # fail it with more than a sentence: the rows behind the failure, laid out the way
  # AllocationRunReportBuild::Finding stores them, so the report can show them as a table.
  #
  #   raise CheckFailed.new("2 entry names are not recognised expense heads",
  #                         columns: ["Entry name", "Entries"], rows: [["Audit fee", 3], ["Bank charge", 1]])
  #
  # A plain `raise "message"` fails a check too; this class only exists to carry rows.
  # See docs/business_requirements/allocation_run_checks.md.
  class CheckFailed < StandardError
    attr_reader :columns, :rows, :filters, :truncated

    # @param summary [String] one line saying what is wrong
    # @param columns [Array<String>] column headings for rows
    # @param rows [Array<Array>] one value array per offending record, in column order
    # @param filters [Array<Array, nil>] parallel to rows: [field, predicate, value] triples for
    #   ransack_query_params_multiple narrowing the account entries screen to that row, or nil
    # @param truncated [Integer] how many further rows exist beyond those passed
    def initialize(summary = nil, columns: [], rows: [], filters: [], truncated: 0)
      super(summary)
      @columns = columns
      @rows = rows
      @filters = filters
      @truncated = truncated
    end
  end
end
