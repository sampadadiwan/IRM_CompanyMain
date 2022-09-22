module HoldingsHelper
  def projected_profits_chart(params, current_user, entity)
    projected_profits = HoldingSummary.new(params, current_user).projected_profits
    logger.debug projected_profits.to_json
    line_chart projected_profits, curve: false, xtitle: "Growth", ytitle: "Estimated Profit",
                                  library: {
                                    plotOptions: {
                                      line: {
                                        dataLabels: {
                                          # enabled: true,
                                          # format: "{point.y:,.2f}"
                                        }
                                      }
                                    }
                                  }, prefix: "#{entity.currency}:"
  end

  def investor_profits_chart(params, current_user, entity)
    projected_profits = InvestorSummary.new(params, current_user).projected_profits
    logger.debug projected_profits.to_json
    line_chart projected_profits, curve: false, xtitle: "Growth", ytitle: "Estimated Profit",
                                  library: {
                                    plotOptions: {
                                      line: {
                                        dataLabels: {
                                          # enabled: true,
                                          # format: "{point.y:,.2f}"
                                        }
                                      }
                                    }
                                  }, prefix: "#{entity.currency}:"
  end
end
