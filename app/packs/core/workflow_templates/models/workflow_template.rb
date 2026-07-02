class WorkflowTemplate < ApplicationRecord
  belongs_to :entity

  has_many :workflow_steps,              -> { order(:position) }, dependent: :destroy, inverse_of: :workflow_template
  has_many :workflow_step_actors,        through: :workflow_steps
  has_many :workflow_assignments,        dependent: :nullify
  has_many :workflow_auto_assignment_rules, dependent: :destroy

  accepts_nested_attributes_for :workflow_steps, allow_destroy: true

  # All workflowable model names that may be scoped to a template.
  # Order matters — this is the order shown in the select dropdown.
  WORKFLOWABLE_TYPE_OPTIONS = %w[Folder InvestorKyc CapitalCommitment Approval].freeze

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

  private

  def workflowable_type_immutable
    return unless workflowable_type_changed? && workflowable_type_was.present?
    errors.add(:workflowable_type, "cannot be changed after it has been set")
  end
end
