# ⑩ Welcome and Getting started reminders (Phase 5, R155):
#   welcome   once, when the firm's compliance setup row is first created — to company admins and users
#             tagged Compliance (H87); recorded in onboarding.welcome_sent_on so it is never repeated (E190)
#   reminders to the compliance owner on day 7 and day 21 after setup started, only while Getting started
#             is incomplete, each once (onboarding.reminders_sent); nothing after day 21 (E189)
# A firm without the Compliance entity flag gets neither (X93). Sent through ComplianceNotices, so
# investors and advisors are never recipients (X35).
# Worked examples H87, E189, E190, X93 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceOnboardingNotices
  REMINDER_DAYS = [7, 21].freeze

  def self.welcome(setup)
    return unless ComplianceAccess.entity_enabled?(setup.entity)
    return if setup.onboarding_hash["welcome_sent_on"].present?

    entity = setup.entity
    admins = User.where(entity_id: entity.id, active: true).select { |u| u.has_cached_role?(:company_admin) }
    recipients = (admins + ComplianceNotices.owners(entity)).uniq.select { |u| ComplianceAccess.viewer?(u) }
    ComplianceNotices.deliver(recipients, entity, "welcome", I18n.t("compliance.notices.welcome", firm: entity.name))
    setup.update_column(:onboarding, setup.onboarding_hash.merge("welcome_sent_on" => Time.zone.today.iso8601))
  end

  # Called from the hourly ComplianceScheduleJob at 08:00 in the firm's time zone
  def self.remind(setup, today)
    return unless ComplianceAccess.entity_enabled?(setup.entity) && setup.owner&.active?

    day = (today - setup.created_at.in_time_zone(setup.time_zone).to_date).to_i
    sent = Array(setup.onboarding_hash["reminders_sent"])
    return unless REMINDER_DAYS.include?(day) && sent.exclude?(day)

    gs = ComplianceGettingStarted.call(entity: setup.entity, user: setup.owner)
    return if gs.complete?

    message = I18n.t("compliance.notices.reminder", done: gs.done_count, next: gs.current.label)
    ComplianceNotices.deliver([setup.owner], setup.entity, "getting_started_reminder", message)
    setup.update_column(:onboarding, setup.onboarding_hash.merge("reminders_sent" => sent + [day]))
  end
end
