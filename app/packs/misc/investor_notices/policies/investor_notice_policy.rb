class InvestorNoticePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.has_cached_role?(:company_admin)
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
