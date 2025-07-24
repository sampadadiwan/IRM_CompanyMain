class InvestorAdvisorPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_investor_advisors && !user.investor_advisor?
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def switch?
    user.has_cached_role?(:investor_advisor) && record.user_id == user.id
  end

  def new?
    create?
  end

  def new_for_investor?
    investor_advisor = record[:investor_advisor]
    investor = record[:investor]
    investor_advisor&.entity_id == investor&.investor_entity_id
  end

  def create_for_investor?
    investor_advisor = record[:investor_advisor]
    investor = record[:investor]
    investor_advisor&.entity_id == investor&.investor_entity_id
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
