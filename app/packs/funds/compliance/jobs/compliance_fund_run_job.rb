# ⑤ Runs one fund's compliance checks for a date. Idempotent: a nightly run per fund and date happens
# once; Run now while one is in flight returns the running one (E18).
class ComplianceFundRunJob < ApplicationJob
  queue_as :low

  def perform(fund_id, run_date, trigger = "nightly", run_at = nil)
    run_at = run_at.present? ? Time.zone.parse(run_at.to_s) : Time.current
    ComplianceRunOperation.call_safely(fund_id:, run_date: Date.parse(run_date.to_s), trigger:, run_at:)
  end
end
