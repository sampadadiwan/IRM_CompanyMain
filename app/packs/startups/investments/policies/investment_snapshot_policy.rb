class InvestmentSnapshotPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id) if user.curr_role == "company"
    end
  end

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
