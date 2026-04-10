module PortfolioHelper
  def share_price_line(investment_instrument)
    valuations = investment_instrument.valuations
    valuations = valuations.group_by { |v| v.valuation_date.strftime("%m/%Y") }
                           .map { |date, vals| [date, vals[-1].per_share_value_cents / 100] }
                           .sort_by { |date, _| Date.strptime(date, "%m/%Y") }
    line_chart valuations, id: "share_price_line_chart_#{investment_instrument.id}", library: {
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

    column_chart cumulative(portfolio_investments), id: "bought_sold_chart_#{aggregate_portfolio_investment.id}", library: {
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

    column_chart xirrs, id: "api_xirr_chart_#{api.id}", library: {
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
    line_chart display_list, id: "portfolio_xirr_lines_chart_#{fund.id}", library: {
      plotOptions: { line: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f} %"
        }
      } },
      **chart_theme_color
    }
  end

  def fetch_ratios_by_name(fund, ratio_names, owners = nil)
    return [] if ratio_names.blank?

    pc_frs = FundRatio.latest.includes(:owner).where(entity_id: fund.entity_id, fund_id: fund.id, name: ratio_names).order(end_date: :desc)
    pc_frs = pc_frs.where(owner: owners) if owners.present?

    return [] if pc_frs.blank?

    # Map the ratios to [portfolio_company_name, ratio_value]
    filtered_frs.map { |fr| { name: fr.owner.name, value: fr.display_value } }
  end

  def fund_ratio_list(owner_ids, fund_ids, owner_types: ["Fund"], ratio_names: %w[IRR])
    return FundRatio.none if owner_ids.blank?

    scope = FundRatio.where(owner_id: owner_ids, owner_type: owner_types, fund_id: fund_ids)
                     .latest
                     .includes(:owner)
                     .order(end_date: :desc)

    scope = scope.where(name: ratio_names) if ratio_names.present?
    scope
  end

  def portfolio_last_xirr(fund)
    pc_frs = FundRatio.latest.where(entity_id: fund.entity_id, fund_id: fund.id, name: "IRR", owner_type: "Investor")
    if pc_frs.present?
      portfolio_irr_ratios = pc_frs.map { |fr| [fr.owner.name, fr.value] }

      column_chart portfolio_irr_ratios, id: "portfolio_last_xirr_chart_#{fund.id}", library: {
        plotOptions: { column: {
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

  def api_last_xirr(fund)
    api_frs = FundRatio.latest.where(entity_id: fund.entity_id, fund_id: fund.id, name: "IRR", owner_type: "AggregatePortfolioInvestment")
    if api_frs.present?
      portfolio_irr_ratios = api_frs.map { |fr| [fr.owner.to_s, fr.value] }
      Rails.logger.debug portfolio_irr_ratios

      column_chart portfolio_irr_ratios, id: "api_last_xirr_chart_#{fund.id}", library: {
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
