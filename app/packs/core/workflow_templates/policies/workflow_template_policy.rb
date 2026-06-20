class WorkflowTemplatePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      # Employees only see templates for their own entity
      scope.where(entity_id: user.entity_id)
    end
  end

  # Scope already filters to user.entity_id; authorize(class) has no .entity_id, so return true
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  # Only company_admin can mutate templates
  def create?
    user.company_admin? && belongs_to_entity?(user, record)
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
end
