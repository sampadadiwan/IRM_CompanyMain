class StockConversionPolicy < FundBasePolicy
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

  def reverse?
    create?
  end

  def update?
    false # permissioned_employee?(:update)
  end

  def edit?
    false # update?
  end

  def destroy?
    false
  end
end
