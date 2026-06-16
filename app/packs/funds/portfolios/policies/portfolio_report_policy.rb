class PortfolioReportPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

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

  def clone?
    create?
  end

  def suggest_sections?
    create?
  end

  def bulk_generate?
    create?
  end
end
