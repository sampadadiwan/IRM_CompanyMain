require "administrate/base_dashboard"

class ValidationRuleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:               Field::Number,
    entity:           Field::BelongsTo,
    target_model:     Field::Select.with_options(collection: ValidationRule::TARGET_MODELS),
    name:             Field::String,
    description:      Field::Text,
    # condition_tree and params are raw JSON — display as text for now;
    # a proper condition-builder UI can replace this in a later iteration
    condition_tree:   JsonField,
    params:           JsonField,
    severity:         Field::Select.with_options(collection: ValidationRule::SEVERITIES),
    message_template: Field::String,
    enabled:          Field::BooleanEmoji,
    is_default:       Field::BooleanEmoji,
    created_by:       Field::BelongsTo,
    created_at:       Field::DateTime,
    updated_at:       Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    entity
    target_model
    name
    severity
    enabled
    is_default
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    entity
    target_model
    name
    description
    condition_tree
    params
    severity
    message_template
    enabled
    is_default
    created_by
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    entity
    target_model
    name
    description
    condition_tree
    params
    severity
    message_template
    enabled
  ].freeze

  COLLECTION_FILTERS = {
    # Filter by model type
    valuation:      ->(resources) { resources.where(target_model: "Valuation") },
    allocation_run: ->(resources) { resources.where(target_model: "AllocationRun") },
    fund_ratio:     ->(resources) { resources.where(target_model: "FundRatio") },
    # Filter by severity
    warnings:       ->(resources) { resources.where(severity: "warning") },
    blockers:       ->(resources) { resources.where(severity: "blocker") },
    # Filter by origin
    defaults:       ->(resources) { resources.where(is_default: true) },
    custom:         ->(resources) { resources.where(is_default: false) },
    # Filter by state
    disabled:       ->(resources) { resources.where(enabled: false) },
    # Show only global defaults (apply to all entities)
    global:         ->(resources) { resources.where(entity_id: nil) }
  }.freeze

  def display_resource(rule)
    "[#{rule.target_model}] #{rule.name}"
  end
end
