# After a statements run succeeds, stores its statement set's checks and unmapped count, and marks
# it refreshed (Draft → ready). Checks are computed from the figures the run wrote, so what the
# screen shows and what was checked are the same numbers. A run that is not the set's current
# statements run is ignored (a stale refresh never overwrites a newer one).
# Worked examples H12, X11 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementRefreshJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 3, wait: :polynomially_longer
  discard_on ActiveRecord::RecordNotFound

  def perform(allocation_run_id)
    # Only the set whose current run this is; a locked set is never touched
    statement = FinancialStatement.find_by(statements_allocation_run_id: allocation_run_id)
    return unless statement&.draft?

    # A failed run leaves the set "Failed" (derived from the run status)
    run = AllocationRun.find(allocation_run_id)
    return unless run.status == "Success"

    fund = statement.fund
    # Fresh calculation: the Unmapped list and the completeness warnings
    result = FinancialStatementCalculator.call(fund:, start_date: statement.start_date, end_date: statement.end_date, setting: statement.setting)
    # Integrity checks over the figures the run actually wrote (what the screen shows)
    checks = FinancialStatementCalculator.checks(fund:, end_date: statement.end_date, figures: statement.figures_from_entries,
                                                 accounts: FinancialStatementCalculator.saved_mapping(fund).accounts,
                                                 setting: statement.setting,
                                                 changes_account_keys: FinancialStatementCalculator.changes_account_keys(fund))
    # Completeness warnings (stale balance, no entries, mixed) come from the fresh calculation
    checks += result.checks.select { |c| c["status"] == "warning" }
    statement.update!(checks:, unmapped_count: result.unmapped.size, refreshed_at: Time.current)
    Rails.logger.info { "FinancialStatementRefreshJob: statement #{statement.id} run #{allocation_run_id} unmapped #{result.unmapped.size}" }
  end
end
