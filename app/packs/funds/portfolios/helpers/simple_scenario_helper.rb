module SimpleScenarioHelper
  def api_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.api_irr(scenarios:)
    # Rails.logger.debug "############# COMPUTE PORTFOLIO IRR #############"
    # Rails.logger.debug values
  end

  def db_portfolio_irr(fund)
    db_xirr = {}

    last_fund_ratio = fund.fund_ratios.last

    if last_fund_ratio
      # Pull out the IRR for the last date only for Portfolio Company
      irrs = fund.fund_ratios.where(name: "IRR", end_date: last_fund_ratio.end_date, owner_type: "AggregatePortfolioInvestment")
      irrs.each do |fund_ratio|
        db_xirr[fund_ratio.owner_id] ||= {}
        db_xirr[fund_ratio.owner_id][:xirr] = fund_ratio.value
      end
    end

    # puts "############# DB XIRR #############"
    # puts db_xirr

    db_xirr
  end

  def get_orig_xirr(_params)
    # orig_xirr = {}

    # if params[:scenario].present?
    #   params[:scenario].each do |k, v|
    #     orig_xirr[k.to_i] = { xirr: v["current_irr"].to_f }
    #   end
    # else
    #   orig_xirr = compute_portfolio_irr(params)
    # end

    # orig_xirr
    db_portfolio_irr(@fund)
  end

  def compute_fund_irr(params, scenarios: nil)
    scenario_date = params[:scenario_date].present? ? Date.parse(params[:scenario_date]) : Time.zone.today
    fpc = FundPortfolioCalcs.new(@fund, scenario_date)
    fpc.xirr(scenarios:)
  end

  def portfolio_company_irr_chart(fund, orig_xirr, scenario_xirr, fund_orig_xirr, fund_scenario_xirr)
    apis = fund.aggregate_portfolio_investments.where(quantity: 1..).order("portfolio_company_name asc")

    oxirr_data = apis.to_h { |api| [api.to_s, orig_xirr[api.id] ? orig_xirr[api.id][:xirr] : 0] }
    oxirr_data[fund.name] = fund_orig_xirr

    sxirr_data = if scenario_xirr.present?
                   apis.to_h { |api| [api.to_s, scenario_xirr[api.id]&.dig(:xirr) || 0] }
                 else
                   apis.to_h { |api| [api.portfolio_company_name, 0] }
                 end

    sxirr_data[fund.name] = fund_scenario_xirr
    chart_data = [{ name: "Current", data: oxirr_data }, { name: "Scenario", data: sxirr_data }]

    Rails.logger.debug chart_data

    # Sample data
    # [{:name=>"Current", :data=>{"Apna Complex"=>838.77, "Cult Fit"=>-69.33}}, {:name=>"Scenario", :data=>{"Apna Complex"=>923.47, "Cult Fit"=>-69.33}}]

    column_chart chart_data,
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}%"
                     }
                   } },
                   **chart_theme_color
                 }
  end
end
