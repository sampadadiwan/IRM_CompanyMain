# The recommended order for moving a fund onto incremental allocation, each step marked done from the
# fund's own data (nothing is stored):
#   1. checks   an enabled post-run check that stored Since Inception totals match history
#   2. baseline a successful allocation run before the switch
#   3. switch   the fund is on incremental allocation
#   4. verify   a successful allocation run after the switch, so the check in step 1 has run on it
#
# The switch time is the latest applied switch-on from the fund formulas page, or, for a fund switched on
# with the rake task (which records no operation), the latest formula edit the migration audited. A fund
# switched on with no formula to edit has no such time, so steps 2 and 4 cannot be told apart and 4
# stays open.
class IncrementalAllocationSteps
  Step = Struct.new(:key, :title, :done, :detail, keyword_init: true)

  def initialize(fund)
    @fund = fund
  end

  def enabled? = CommitmentAccountEntry.incremental_since_inception?(@fund)

  def switched_at
    return @switched_at if defined?(@switched_at)

    @switched_at = ([applied_switch_at, audited_switch_at].compact.max if enabled?)
  end

  def steps
    @steps ||= [checks_step, baseline_step, switch_step, verify_step]
  end

  # The first step not done, or nil
  def next_step = steps.find { |s| !s.done }

  private

  def checks_step
    check = @fund.fund_formulas.post_run_checks.enabled.where("formula LIKE ?", "since_inception_matches_history%").first
    Step.new(key: :checks, title: "Add run checks, including \"Since Inception totals match history\"", done: check.present?,
             detail: check ? "#{@fund.fund_formulas.run_checks.enabled.count} enabled run checks; seq #{check.sequence} #{check.name}" : "Use Actions > Suggest run checks")
  end

  def baseline_step
    before = successful_runs
    before = before.where(created_at: ...switched_at) if switched_at
    run = before.first
    Step.new(key: :baseline, title: "Re-run the latest period before switching", done: run.present?,
             detail: run ? run_detail(run) : "Run the latest period from the allocation screen")
  end

  def switch_step
    detail = if switched_at then "Switched on #{I18n.l(switched_at, format: :abbr_date_time)}"
             elsif enabled? then "Switched on outside this page"
             else "Preview and apply \"Switch to incremental\" below"
             end
    Step.new(key: :switch, title: "Preview and apply the switch", done: enabled?, detail:)
  end

  def verify_step
    run = switched_at && successful_runs.where(created_at: switched_at..).first
    detail = if run then run_detail(run)
             elsif enabled? && !switched_at then "Switched on outside this page, so the run after the switch cannot be identified"
             else "Re-run the latest period after switching; the post-run check confirms the carried totals"
             end
    Step.new(key: :verify, title: "Re-run the latest period after switching", done: run.present?, detail:)
  end

  def successful_runs
    AllocationRun.where(fund_id: @fund.id).successful.order(created_at: :desc)
  end

  def applied_switch_at
    FundFormulaOperation.where(fund_id: @fund.id, operation: "enable_incremental", status: "applied").maximum(:applied_at)
  end

  # Every formula edit the switch-on makes is audited with the migration's comment, whichever way it ran
  def audited_switch_at
    Audited::Audit.where(auditable_type: "FundFormula", auditable_id: @fund.fund_formulas.select(:id),
                         comment: AccountEntryAllocation::IncrementalMigration::AUDIT_COMMENT).maximum(:created_at)
  end

  def run_detail(run)
    "Run ##{run.id}, #{I18n.l(run.start_date)} to #{I18n.l(run.end_date)}, #{I18n.l(run.created_at, format: :abbr_date_time)}"
  end
end
