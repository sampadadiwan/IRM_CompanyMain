class InvestmentOpportunityPolicy < IoBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    user.enable_inv_opportunities
  end

  def show?
    user.enable_inv_opportunities &&
      (
        permissioned_employee? ||
        permissioned_investor?
      )
  end

  def create?
    user.enable_inv_opportunities && permissioned_employee?
  end

  def new?
    user.enable_inv_opportunities && ["Investment Fund"].include?(user.entity_type)
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
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
