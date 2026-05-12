class ValidationRule < ApplicationRecord
  # ── Constants ────────────────────────────────────────────────────────────────

  SEVERITIES = %w[warning blocker].freeze

  # Extend this list when wiring new models into the engine
  TARGET_MODELS = %w[Valuation AllocationRun FundRatio].freeze

  # ── Associations ─────────────────────────────────────────────────────────────

  # entity_id is NULL for global default rules; non-NULL for entity-specific custom rules
  belongs_to :entity, optional: true

  belongs_to :created_by, class_name: "User", optional: true

  # Overrides let a tenant disable a default rule or replace its param values
  has_many :validation_rule_overrides, dependent: :destroy

  # ── Validations ──────────────────────────────────────────────────────────────

  validates :name, presence: true
  validates :target_model, presence: true, inclusion: { in: TARGET_MODELS }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :message_template, presence: true
  validates :condition_tree, presence: true

  # MySQL JSON columns return nil instead of {} when empty — normalise here
  attribute :condition_tree, :json, default: {}
  attribute :params,         :json, default: {}

  # ── Scopes ───────────────────────────────────────────────────────────────────

  # Global defaults have no entity — available to all tenants
  scope :global_defaults, -> { where(entity_id: nil, is_default: true) }

  # Rules that belong exclusively to one entity
  scope :for_entity, ->(entity_id) { where(entity_id:) }

  scope :for_model, ->(model) { where(target_model: model) }
  # Used only for entity-specific custom rules. Global defaults use the override-wins
  # logic in ValidationRuleEvaluator#resolve_active_rules rather than this scope.
  scope :enabled,   -> { where(enabled: true) }

  # ── Helpers ──────────────────────────────────────────────────────────────────

  def warning? = severity == "warning"
  def blocker?  = severity == "blocker"

  # True when this is a global default that can be overridden per entity
  def global? = entity_id.nil? && is_default
end
