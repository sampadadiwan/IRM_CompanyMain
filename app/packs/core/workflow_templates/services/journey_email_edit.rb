# An investor email (custom notification) was created, edited or deleted: the journey's "Review email"
# and "Check preview" confirmations no longer cover what investors will receive, so they are reset
# and the journey re-checked as an undo.
#
# A record's own notification affects that record; a fund-level one (for_type = the record type)
# affects every record of the fund that has not emailed investors yet — a review after sending
# can't change anything (capital-call-journey design Decision 15).
#
# One entry in CONFIGS per record type with a journey. Moved here from CapitalCallJourneyEmailEdit
# so distributions share it (capital-distribution-journey design Decision 10).
# Worked examples E12, E24 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
# Worked examples E14 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
class JourneyEmailEdit
  REASON = "Email template changed after review".freeze

  # record type => the review tasks to reset, and the task that says investors were emailed
  CONFIGS = {
    "CapitalCall" => {
      review_keys: %w[capital_call.review_email capital_call.check_preview].freeze,
      sent_key: "capital_call.send_notices"
    },
    "CapitalDistribution" => {
      review_keys: %w[capital_distribution.review_email capital_distribution.check_preview].freeze,
      sent_key: "capital_distribution.email_investors"
    }
  }.freeze

  def self.call(notification:, actor:, started_at:)
    CONFIGS.each do |type, config|
      records_for(notification, type).find_each do |record|
        # Decided from the data, not the step's cached status: a record can have emailed investors
        # while its journey is still stopped at an earlier task (e.g. not approved), which shows
        # the sent task as "not yet"
        next if WorkflowChecks::Registry.fetch(config[:sent_key]).call(record).passed?

        WorkflowStepInvalidate.call(record:, check_keys: config[:review_keys], actor:, reason: REASON)
        record.journey_undo_evaluate(note: REASON, actor:, started_at:)
      end
    end
  rescue StandardError => e
    Rails.logger.error("[JourneyEmailEdit] notification #{notification.id}: #{e.message}")
    ExceptionNotifier.notify_exception(e, data: { custom_notification_id: notification.id })
  end

  # Records of `type` whose journey the notification can affect, limited to ones that have a journey
  def self.records_for(notification, type)
    klass = type.constantize # a CONFIGS key, never user input
    scope = if notification.owner_type == type
              klass.where(id: notification.owner_id)
            elsif notification.owner_type == "Fund" && notification.for_type == type
              klass.where(fund_id: notification.owner_id)
            else
              klass.none
            end
    scope.where(id: WorkflowInstance.evaluated.where(workflowable_type: type).where.not(status: :archived)
                                    .select(:workflowable_id))
  end
end
