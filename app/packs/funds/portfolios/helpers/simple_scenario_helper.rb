module SimpleScenarioHelper
  def compute_portfolio_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.portfolio_company_irr(scenarios:)
  end

  def compute_fund_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.xirr(scenarios:)
  end
end
