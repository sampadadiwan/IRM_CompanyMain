class FundingRoundPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || support?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create? || support?
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
