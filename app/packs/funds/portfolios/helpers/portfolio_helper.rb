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

  def fund_ratio_list(owner_ids, fund_ids, owner_types: ["Fund"], ratio_names: %w[IRR], latest: true, end_date: nil, scenario: nil, scenarios: nil, months: nil)
    result = FundRatioList.call(current_user, { owner_id: owner_ids, fund_id: fund_ids, owner_type: owner_types, name: ratio_names, latest:, end_date:, scenario:, scenarios: })
    fund_ratios = result.fund_ratios
    fund_ratios = fund_ratios.where("end_date >= ?", months.to_i.months.ago.to_date) if months.present? && end_date.nil?
    fund_ratios
  end

  def multi_fund_cross_portfolio_ratios(fund_ids, investor_ids, owner_types: ["Fund"], ratio_names: %w[IRR], latest: true, latest_run_only: false, end_date: nil, scenario: nil, scenarios: nil)
    runs = cross_portfolio_runs_for(fund_ids, investor_ids, current_user.entity_id)

    # No runs computed yet — return nil so the caller can render a "Generate" prompt.
    return nil if runs.none?

    fund_ratios = FundRatio.where(
      entity_id:                current_user.entity_id,
      computation_context_type: "FundRatioRun",
      computation_context_id:   runs.ids,
      owner_type:               owner_types,
      name:                     ratio_names
    )

    fund_ratios = fund_ratios.where(latest: true) if latest
    fund_ratios = fund_ratios.where(end_date:) if end_date.present?

    # For aggregate (Fund-owner) ratios, keep only the most recently computed
    # end_date so historical re-runs don't produce duplicate rows.
    if latest_run_only && fund_ratios.any?
      max_end_date = fund_ratios.maximum(:end_date)
      fund_ratios = fund_ratios.where(end_date: max_end_date)
    end

    # `scenarios` is a comma-separated widget arg, not a DB column — parse before filtering
    if scenarios.present?
      fund_ratios = fund_ratios.where(scenario: scenarios.split(",").map(&:strip))
    elsif scenario.present?
      fund_ratios = fund_ratios.where(scenario:)
    end

    fund_ratios.order(end_date: :desc)
  end

  # Finds FundRatioRun records that exactly match the supplied fund combination
  # using the SHA-256 fingerprint stored in the `name` column.
  # Returns none if no exact run exists — no broad/fuzzy fallback.
  def cross_portfolio_runs_for(fund_ids, investor_ids, entity_id)
    fund_ids     = Array(fund_ids).map(&:to_i).reject(&:zero?)
    investor_ids = Array(investor_ids).map(&:to_i).reject(&:zero?)

    FundRatioRun.where(entity_id:)
                .where(name: FundRatioRun.fingerprint(fund_ids:, portfolio_company_ids: investor_ids))
                .order(end_date: :desc)
  end

  def portfolio_last_xirr(fund)
    pc_frs = FundRatio.latest.where(entity_id: fund.entity_id, fund_id: fund.id, name: %w[IRR MOIC], owner_type: "Investor").includes(:owner)
    if pc_frs.present?
      grouped = pc_frs.group_by { |fr| fr.owner.name }
      chart_data = [
        { name: "IRR", data: grouped.map { |name, ratios| [name, ratios.find { |r| r.name == "IRR" }&.value || 0] } },
        { name: "MOIC", data: grouped.map { |name, ratios| [name, ratios.find { |r| r.name == "MOIC" }&.value || 0] } }
      ]

      options = {
        library: {
          plotOptions: { column: {
            dataLabels: {
              enabled: true,
              format: "{point.y:,.2f}"
            }
          } },
          **chart_theme_color
        }
      }
      options[:colors] = pie_chart_colors_from_css if use_custom_colors?

      column_chart chart_data, id: "portfolio_last_xirr_chart_#{fund.id}", **options
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
