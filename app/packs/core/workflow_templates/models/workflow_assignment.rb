class WorkflowAssignment < ApplicationRecord
  belongs_to :workflowable, polymorphic: true
  belongs_to :workflow_template
  belongs_to :created_by, class_name: "User", optional: true

  # One assignment per object at a time
  validates :workflowable_id, uniqueness: { scope: :workflowable_type,
    message: "already has a workflow template assigned" }

  validate :template_must_belong_to_entity
  validate :template_type_matches_workflowable

  before_destroy :block_if_active_instance

  private

  def template_type_matches_workflowable
    return unless workflow_template&.workflowable_type.present? && workflowable_type.present?
    expected = workflow_template.workflowable_type
    actual   = workflowable_type
    unless expected == actual
      errors.add(:workflow_template, "is scoped to #{expected} and cannot be assigned to #{actual}")
    end
  end

  def template_must_belong_to_entity
    return unless workflowable.respond_to?(:entity_id) && workflow_template
    unless workflow_template.entity_id == workflowable.entity_id
      errors.add(:workflow_template, "must belong to the same organisation")
    end
  end

  def block_if_active_instance
    active = WorkflowInstance.where(workflowable: workflowable).instance_active
    # Deleting the record itself (this assignment goes with it via dependent: :destroy) while only an
    # evaluated journey is active: let it go — a journey is advisory tracking, and every new capital
    # call has one, so blocking here made such calls undeletable. Unassigning a live workflow, or
    # deleting a record mid human-approval workflow, is still refused as before.
    # Worked examples E17 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    return if destroyed_by_association && !active.exists?(evaluated: false)

    if active.exists?
      errors.add(:base, "Cannot remove the workflow assignment while a workflow is active. Archive the active workflow first.")
      throw :abort
    end
  end
end
