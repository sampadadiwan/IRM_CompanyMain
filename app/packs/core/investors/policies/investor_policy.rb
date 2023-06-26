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
      (user.entity_id == record.entity_id || user.entity_id == record.investor_entity_id || super_user?)
  end

  def create?
    (user.enable_investors && user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create? || super_user?
  end

  def merge?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
