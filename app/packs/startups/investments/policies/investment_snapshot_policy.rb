class InvestmentSnapshotPolicy < ApplicationPolicy
  def index?
    user.enable_investments
  end

  def show?
    true
  end

  def create?
    false
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
