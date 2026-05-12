class ValidationRuleOverride < ApplicationRecord
  # ── Associations ─────────────────────────────────────────────────────────────

  # The global default rule this override targets
  belongs_to :validation_rule

  # The tenant applying this override
  belongs_to :entity

  belongs_to :created_by, class_name: "User", optional: true

  # ── Validations ──────────────────────────────────────────────────────────────

  # Only one override per (rule, entity) pair
  validates :validation_rule_id, uniqueness: { scope: :entity_id }

  # Normalise MySQL JSON columns to empty hash instead of nil
  attribute :param_overrides, :json, default: {}

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Merge this entity's param overrides on top of the rule's global defaults.
  # The result is what gets passed to the condition evaluator.
  def resolved_params
    validation_rule.params.merge(param_overrides || {})
  end

  # The message to display: entity override takes priority over the rule default
  def resolved_message
    message_override.presence || validation_rule.message_template
  end

  # The severity to use: entity override takes priority over the rule default.
  # Allows a tenant to escalate a warning to a blocker (or downgrade a blocker to a warning).
  def resolved_severity
    severity_override.presence || validation_rule.severity
  end
end
