module SimpleScenarioHelper
  def compute_portfolio_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.portfolio_company_irr(scenarios:)
  end

  def get_orig_xirr(params)
    orig_xirr = {}

    if params[:scenario].present?
      params[:scenario].each do |k, v|
        orig_xirr[k.to_i] = { xirr: v["current_irr"].to_f }
      end
    else
      orig_xirr = compute_portfolio_irr(params)
    end

    orig_xirr
  end

  def compute_fund_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.xirr(scenarios:)
  end

  def portfolio_company_irr_chart(fund, orig_xirr, scenario_xirr, fund_orig_xirr, fund_scenario_xirr)
    apis = fund.aggregate_portfolio_investments.where(quantity: 1..).order("portfolio_company_name asc")

    oxirr_data = apis.to_h { |api| [api.portfolio_company_name, orig_xirr[api.portfolio_company_id][:xirr]] }
    oxirr_data[fund.name] = fund_orig_xirr

    sxirr_data = apis.to_h { |api| [api.portfolio_company_name, scenario_xirr[api.portfolio_company_id][:xirr]] }
    sxirr_data[fund.name] = fund_scenario_xirr

    chart_data = [{ name: "Current", data: oxirr_data }, { name: "Scenario", data: sxirr_data }]
    Rails.logger.debug chart_data

    # Sample data
    # [{:name=>"Current", :data=>{"Apna Complex"=>838.77, "Cult Fit"=>-69.33}}, {:name=>"Scenario", :data=>{"Apna Complex"=>923.47, "Cult Fit"=>-69.33}}]

    column_chart chart_data, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}%"
        }
      } }
    }
  end
end
