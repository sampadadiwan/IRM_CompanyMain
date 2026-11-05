# ⑤ Hourly tick (sidekiq-cron "5 * * * *"). For each entity with monitoring on, in the entity's local time:
#   02:00 → one ComplianceFundRunJob per fund with an active pack (H19, E29)
#   08:00 → reassign items of deactivated users (R12), escalate overdue items (E36), version notices
#           7 days ahead (E87), then the digest (H29, E45)
# Entities with monitoring off are skipped — no runs, no backfill (E133).
class ComplianceScheduleJob < ApplicationJob
  queue_as :low

  RUN_HOUR = 2
  DIGEST_HOUR = 8

  def perform(now: Time.current)
    ComplianceEntitySetup.where(monitoring_enabled: true).includes(:entity).find_each do |setup|
      local = now.in_time_zone(setup.time_zone)
      run_funds(setup, local.to_date) if local.hour == RUN_HOUR
      morning(setup, local.to_date) if local.hour == DIGEST_HOUR
    rescue StandardError => e
      Rails.logger.error("[ComplianceScheduleJob] entity #{setup.entity_id}: #{e.class}")
    end
  end

  def run_funds(setup, local_date)
    fund_ids = FundCompliancePack.active.where(entity_id: setup.entity_id).distinct.pluck(:fund_id)
    fund_ids.each { |id| ComplianceFundRunJob.perform_later(id, local_date.iso8601, "nightly") }
  end

  def morning(setup, local_date)
    ComplianceMaintenance.reassign_deactivated(setup)
    ComplianceMaintenance.escalate_overdue(setup.entity, local_date)
    ComplianceMaintenance.version_reminders(setup.entity, local_date)
    ComplianceDigestJob.perform_later(setup.entity_id, local_date.iso8601)
  end
end
