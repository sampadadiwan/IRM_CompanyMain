class PortfolioCashflowPolicy < FundBasePolicy
  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  def report?
    update?
  end

  def show?
    user.entity.permissions.enable_fund_portfolios? &&
      permissioned_employee?
  end

  def create?
    user.entity.permissions.enable_fund_portfolios? &&
      permissioned_employee?
  end

  def new?
    create?
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
end
