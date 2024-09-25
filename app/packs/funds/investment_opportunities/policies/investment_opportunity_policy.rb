class InvestmentOpportunityPolicy < IoBasePolicy
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
    user.enable_inv_opportunities && permissioned_employee?(:create)
  end

  def new?
    user.enable_inv_opportunities
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
