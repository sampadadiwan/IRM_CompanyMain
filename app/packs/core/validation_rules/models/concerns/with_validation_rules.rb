module WithValidationRules
  extend ActiveSupport::Concern

  included do
    # Enforce blocker-severity rules on every create/update, just like a standard
    # ActiveRecord validation. Warnings are ignored here — they are UI-only feedback.
    validate :enforce_blocker_rules, on: %i[create update]
  end

  # ── Escape hatch ────────────────────────────────────────────────────────────
  #
  # Use this when a background job or script legitimately needs to bypass the
  # rule engine (e.g. a migration, a seed task, or an automated reprocessing
  # run that you know is safe):
  #
  #   WithValidationRules.skip { allocation_run.save! }
  #
  # The skip is thread-local so it never leaks across concurrent requests.
  def self.skip
    Thread.current[:skip_validation_rules] = true
    yield
  ensure
    Thread.current[:skip_validation_rules] = false
  end

  private

  def enforce_blocker_rules
    # Honour the escape hatch
    return if Thread.current[:skip_validation_rules]

    # Only run for models the engine has a ContextProvider for
    return unless ValidationRuleEvaluator::CONTEXT_PROVIDERS.key?(self.class.name)

    # Derive entity from the record itself — no current_user available here
    entity = try(:entity) || Entity.find_by(id: entity_id)
    return unless entity

    ValidationRuleEvaluator.call(record: self, entity: entity)
                           .select(&:blocker?)
                           .each { |result| errors.add(:base, result.message) }
  rescue StandardError => e
    # A broken rule engine must never silently block legitimate saves —
    # log the error and allow the save to continue
    Rails.logger.error("[WithValidationRules] Rule evaluation failed for #{self.class.name}##{id}: #{e.message}")
  end
end
