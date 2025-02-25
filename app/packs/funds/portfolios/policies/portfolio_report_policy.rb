class PortfolioReportPolicy < FundBasePolicy
  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  def generate?
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
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
