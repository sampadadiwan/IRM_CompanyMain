class InvestorPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      (user.entity_id == record.entity_id || user.entity_id == record.investor_entity_id)
  end

  def create?
    user.enable_investors && user.entity_id == record.entity_id
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
    # TODO: - check for key dependency and allow/deny delete
    false
  end
end
