class FundingRoundPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) || super_user?
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create? || super_user?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def approve_all_holdings?
    create? && user.has_cached_role?(:approver)
  end
end
