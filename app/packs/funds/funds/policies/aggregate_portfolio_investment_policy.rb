class AggregatePortfolioInvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == 'employee' && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id)
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
    update?
  end

  def destroy?
    (user.entity_id == record.entity_id)
  end
end
