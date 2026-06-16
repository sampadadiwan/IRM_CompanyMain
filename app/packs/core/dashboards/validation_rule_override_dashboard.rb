require "administrate/base_dashboard"

class ValidationRuleOverrideDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    # The global default rule being overridden
    validation_rule: Field::BelongsTo,
    entity: Field::BelongsTo,
    enabled: Field::BooleanEmoji,
    # JSON hash of param values that replace the rule's defaults for this entity
    param_overrides: JsonField,
    message_override: Field::String,
    created_by: Field::BelongsTo,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    entity
    validation_rule
    enabled
    param_overrides
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    entity
    validation_rule
    enabled
    param_overrides
    message_override
    created_by
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    entity
    validation_rule
    enabled
    param_overrides
    message_override
  ].freeze

  COLLECTION_FILTERS = {
    disabled: ->(resources) { resources.where(enabled: false) }
  }.freeze

  def display_resource(override)
    "#{override.entity&.name} / #{override.validation_rule&.name}"
  end
end
