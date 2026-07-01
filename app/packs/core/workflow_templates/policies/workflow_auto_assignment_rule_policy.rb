class WorkflowAutoAssignmentRulePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  # Only company_admin can manage auto-assignment rules; the feature must also be enabled
  def index?
    workflow_templates_enabled? && user.company_admin?
  end

  def show?
    workflow_templates_enabled? && belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def create?
    workflow_templates_enabled? && user.company_admin? && belongs_to_entity?(user, record)
  end

  def edit?
    update?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  private

  def workflow_templates_enabled?
    user.entity&.permissions&.enable_workflow_templates?
  end
end
