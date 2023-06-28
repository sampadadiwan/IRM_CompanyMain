class InvestorPolicy < ApplicationPolicy
  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      (belongs_to_entity?(user, record) || user.entity_id == record.investor_entity_id || super_user?)
  end

  def create?
    (user.enable_investors && belongs_to_entity?(user, record))
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
