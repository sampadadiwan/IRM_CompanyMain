module PortfolioHelper

    def share_price_line(portfolio_company)
        valuations = portfolio_company.valuations
        valuations = valuations.group_by{|v| v.valuation_date.strftime("%m/%Y")}
                               .map {|date, vals| [date, vals[-1].per_share_value_cents/100]}
                                                     
        line_chart valuations, library: {
          plotOptions: { column: {
            dataLabels: {
              enabled: true,
              format: "{point.y:,.2f}"
            }
          } }
        }
    end


    def bought_sold(aggregate_portfolio_investment)
        
        portfolio_investments = aggregate_portfolio_investment.portfolio_investments
        portfolio_investments = aggregate_portfolio_investment.portfolio_investments.group_by_quarter(:investment_date, format: "%m/%Y").sum(:quantity)

        cum_portfolio_investments = portfolio_investments.inject([]) { |x, y| x << (x.last || 0 ) + y }
        
        line_chart cum_portfolio_investments, library: {
          plotOptions: { column: {
            dataLabels: {
              enabled: true,
              format: "{point.y:,.2f}"
            }
          } }
        }
    end
end