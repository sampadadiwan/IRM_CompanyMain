module PortfolioHelper
  def investment_fmv_by_company(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d] }

    pie_chart_with_options grouped
  end

  def bought_sold_fmv(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d, k.bought_amount.to_d, k.sold_amount.to_d] }

    column_chart [
      { name: "FMV", data: grouped.map { |k| [k[0], k[1]] } },
      { name: "Bought", data: grouped.map { |k| [k[0], k[2]] } },
      { name: "Sold", data: grouped.map { |k| [k[0], k[3]] } }
    ]
  end

  def share_price_line(portfolio_company)
    valuations = portfolio_company.valuations
    valuations = valuations.group_by { |v| v.valuation_date.strftime("%m/%Y") }
                           .map { |date, vals| [date, vals[-1].per_share_value_cents / 100] }

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
    portfolio_investments = aggregate_portfolio_investment.portfolio_investments.order(investment_date: :asc)
                                                          .group_by { |v| v.investment_date.strftime("%m/%Y") }
                                                          .map { |date, vals| [date, vals.inject(0) { |sum, pi| sum + pi.quantity }] }

    column_chart cumulative(portfolio_investments), library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } }
    }
  end

  def cumulative(portfolio_investments)
    portfolio_investments.inject([]) do |array, dq|
      last_qty = array.last ? array.last[1] : 0
      array << [dq[0], dq[1] + last_qty]
    end
  end
end
