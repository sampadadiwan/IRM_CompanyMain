class WorkflowTemplate < ApplicationRecord
  belongs_to :entity

  has_many :workflow_steps,              -> { order(:position) }, dependent: :destroy, inverse_of: :workflow_template
  has_many :workflow_step_actors,        through: :workflow_steps
  has_many :workflow_assignments,        dependent: :nullify
  has_many :workflow_auto_assignment_rules, dependent: :destroy

  accepts_nested_attributes_for :workflow_steps, allow_destroy: true

  # All workflowable model names that may be scoped to a template.
  # Order matters — this is the order shown in the select dropdown.
  # "Investor" covers both regular investors (onboarding) and portfolio companies
  # (KPI report review) — the two use cases are distinguished by `category` in the
  # auto-assignment rule's conditions, not by a separate workflowable_type.
  WORKFLOWABLE_TYPE_OPTIONS = %w[Folder InvestorKyc CapitalCommitment CapitalCall Approval Investor].freeze

  before_validation { self.workflowable_type = nil if workflowable_type.blank? }

  validates :name, presence: true
  validates :name, uniqueness: { scope: :entity_id, message: "must be unique within your organisation" }
  validates :workflowable_type, inclusion: { in: WORKFLOWABLE_TYPE_OPTIONS, message: "is not a valid workflowable type" },
                                allow_nil: true, allow_blank: true

  # workflowable_type is immutable once set — changing it would orphan existing assignments
  validate :workflowable_type_immutable, on: :update

  def to_s
    name
  end

  # Number of objects currently assigned to this template across all workflowable types
  def active_workflowable_count
    workflow_assignments.count
  end

  # Templates scoped to a specific type (or with no type set) that match the given class name
  def self.for_workflowable_type(type_name)
    where(workflowable_type: [type_name, nil])
  end

  # Whether this template could plausibly apply to the given record. workflowable_type alone
  # is too coarse when one type covers multiple sub-audiences — e.g. "Investor" spans both
  # regular investors and portfolio companies, distinguished only by `category` in a
  # WorkflowAutoAssignmentRule's conditions, not by a column on WorkflowTemplate itself. So:
  # a template with no auto-assignment rules for this type has no known restriction (eligible);
  # a template whose rules ALL evaluate false against this exact record could never have been
  # auto-assigned to it, which is a strong signal it's scoped to a different sub-audience.
  def eligible_for?(workflowable)
    rules = workflow_auto_assignment_rules.where(workflowable_type: workflowable.class.name)
    return true if rules.none?
    rules.any? { |rule| rule.matches?(workflowable) }
  end

  private

  def workflowable_type_immutable
    return unless workflowable_type_changed? && workflowable_type_was.present?
    errors.add(:workflowable_type, "cannot be changed after it has been set")
  end
end
