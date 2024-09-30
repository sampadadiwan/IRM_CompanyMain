module PortfolioHelper
  def share_price_line(investment_instrument)
    valuations = investment_instrument.valuations
    valuations = valuations.group_by { |v| v.valuation_date.strftime("%m/%Y") }
                           .map { |date, vals| [date, vals[-1].per_share_value_cents / 100] }
                           .sort_by { |date, _| Date.strptime(date, "%m/%Y") }
    line_chart valuations, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } },
      **chart_theme_color
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
      } },
      **chart_theme_color
    }
  end

  def api_xirr_chart(api)
    xirrs = FundRatio.where(entity_id: api.entity_id, fund_id: api.fund_id,
                            owner: api,
                            name: "IRR")
                     .order(end_date: :asc)
                     .pluck(:end_date, :value)

    column_chart xirrs, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f} %"
        }
      } },
      **chart_theme_color
    }
  end

  def portfolio_xirr_lines(fund)
    portfolio_irr_ratios = FundRatio.where(entity_id: fund.entity_id, fund_id: fund.id)
                                    .order(end_date: :asc)
                                    .where("name like 'IRR%'").group_by(&:name)

    display_list = portfolio_irr_ratios.map { |name, ratios| { name:, data: ratios.map { |r| [r.end_date, r.value] } } }
    line_chart display_list, library: {
      plotOptions: { line: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f} %"
        }
      } },
      **chart_theme_color
    }
  end

  def portfolio_last_xirr(fund)
    api_frs = FundRatio.latest.where(entity_id: fund.entity_id, fund_id: fund.id, name: "IRR", owner_type: "AggregatePortfolioInvestment")
    if api_frs.present?
      portfolio_irr_ratios = api_frs.map { |fr| [fr.owner.to_s, fr.value] }

      column_chart portfolio_irr_ratios, library: {
        plotOptions: { line: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f} %"
          }
        } },
        **chart_theme_color
      }
    else
      "No data available."
    end
  end

  def cumulative(portfolio_investments)
    portfolio_investments.inject([]) do |array, dq|
      last_qty = array.last ? array.last[1] : 0
      array << [dq[0], dq[1] + last_qty]
    end
  end
end
