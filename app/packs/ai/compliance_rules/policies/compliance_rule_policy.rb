class ComplianceRulePolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_compliance
  end

  def show?
    user.enable_compliance &&
      belongs_to_entity?(user, record)
  end

  def create?
    belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)
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
    update?
  end
end
