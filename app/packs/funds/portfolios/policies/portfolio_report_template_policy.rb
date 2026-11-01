class PortfolioReportTemplatePolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      scope.joins(:portfolio_report).where(portfolio_reports: { entity_id: user.entity_id })
    end
  end

  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  # M20 — a template is its portfolio report's firm's (entity_id is delegated to the report); other
  # tenants are refused (M20-X1, M20-H1)
  def show?
    index? && belongs_to_entity?(user, record)
  end

  # M20 — writes (and update / edit / destroy, which follow this) also need the firm check (M20-X2)
  def create?
    show? && user.has_cached_role?(:company_admin)
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
