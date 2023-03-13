class PortfolioInvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  # No updates to investments as the current algorith for attribution cannot handle updates
  # So delete and create if you want to update
  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end
end
