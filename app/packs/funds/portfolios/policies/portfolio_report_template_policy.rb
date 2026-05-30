class PortfolioReportTemplatePolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      scope.joins(:portfolio_report).where(portfolio_reports: { entity_id: user.entity_id })
    end
  end

  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  def show?
    index?
  end

  def create?
    index? && user.has_cached_role?(:company_admin)
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
