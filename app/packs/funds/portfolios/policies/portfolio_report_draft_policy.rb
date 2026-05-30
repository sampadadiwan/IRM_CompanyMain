class PortfolioReportDraftPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      scope.joins(:portfolio_report).where(portfolio_reports: { entity_id: user.entity_id })
    end
  end

  def show?
    fund_portfolios_enabled? && permissioned_employee?
  end

  def approve?
    show?
  end

  def approve_and_export?
    show?
  end

  def preview?
    show?
  end

  def reopen?
    show?
  end

  def export?
    show?
  end

  def update_kpi_cell?
    show?
  end

  def update_section?
    show?
  end

  def regenerate_section?
    show?
  end

  private

  def fund_portfolios_enabled?
    user.entity.permissions.enable_fund_portfolios?
  end
end
