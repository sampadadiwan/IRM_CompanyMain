# Whether something is changing a fund's allocation right now, so that nothing else starts on top of it:
#   - an allocation run group that is using (or has yet to reach) the fund
#   - an allocation run on the fund that has not finished
#   - a fund formula operation (switch to incremental, recompute starting values, ...) still in progress
#   - a tracking currency change (ChangeTrackingCurrencyJob) in progress, or failed and awaiting a retry
#
# A run or operation still "in progress" after FundFormulaOperation::STALE_AFTER is taken to have crashed:
# its status would otherwise block the fund for ever.
#
#   FundAllocationActivity.new(fund).reason                 # nil when idle, else a sentence for the user
#   FundAllocationActivity.new(fund).reason(except: op)     # ignoring the operation asking
#   FundAllocationActivity.formula_operation_applying?(fund) # what allocation runs refuse on
class FundAllocationActivity
  # AllocationRun#status is blank until the job starts and "Pending" while it runs
  UNFINISHED_RUN_STATUSES = [nil, "", "Pending"].freeze

  def self.busy?(fund) = new(fund).reason.present?

  # An operation that is writing formulas, starting values and the incremental flag. A run starting
  # now could load formulas from before the write and the flag from after it.
  def self.formula_operation_applying?(fund)
    FundFormulaOperation.live.exists?(fund_id: fund.id, status: "applying")
  end

  def initialize(fund)
    @fund = fund
  end

  # @param except [FundFormulaOperation, nil] the operation doing the asking
  # @return [String, nil]
  def reason(except: nil)
    return "An allocation run group is currently running on this fund. Wait for it to finish." if AllocationGroupRun.fund_busy?(@fund.id)
    return "An allocation run on this fund has not finished yet. Wait for it to finish." if unfinished_run?
    return "The fund's tracking currency is being changed. Wait for it to finish." if @fund.tracking_currency_change_pending?

    operation = FundFormulaOperation.live.where(fund_id: @fund.id).where.not(id: except&.id).first
    "#{operation} is still #{operation.status} on this fund. Wait for it to finish." if operation
  end

  private

  def unfinished_run?
    AllocationRun.exists?(fund_id: @fund.id, status: UNFINISHED_RUN_STATUSES, created_at: FundFormulaOperation::STALE_AFTER.ago..)
  end
end
