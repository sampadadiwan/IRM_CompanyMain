class WorkflowStepPolicy < ApplicationPolicy
  # Inherit entity check via parent template
  delegate :company_admin?, to: :user

  def create?
    company_admin? && belongs_to_entity?(user, record.workflow_template)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end

  # Used by WorkflowStepsController#reorder
  def reorder?
    create?
  end
end
