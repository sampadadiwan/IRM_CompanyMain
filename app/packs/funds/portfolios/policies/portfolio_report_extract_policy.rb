class PortfolioReportExtractPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.entity.permissions.enable_fund_portfolios?
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

  # X15: deleting is stricter than editing: company admins only
  def destroy?
    create? && user.has_cached_role?(:company_admin)
  end

  def generate_tear_sheet?
    show?
  end

  def update_slides_content?
    update?
  end
end
