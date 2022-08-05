class InvestmentOpportunityPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "fund_manager"
        scope.where(entity_id: user.entity_id)
      else
        InvestmentOpportunity.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      InvestmentOpportunity.for_investor(user).where(id: record.id).present?
  end

  def create?
    (user.entity_id == record.entity_id)
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
    update?
  end

  def allocate?
    update?
  end

  def toggle?
    update?
  end

  def send_notification?
    update?
  end

  def finalize_allocation?
    update?
  end
end
