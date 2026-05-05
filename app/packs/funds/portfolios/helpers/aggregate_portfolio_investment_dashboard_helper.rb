module AggregatePortfolioInvestmentDashboardHelper
  def portfolio_allocation_by_company_chart(fund, compact: false)
    data = fund.aggregate_portfolio_investments.group(:portfolio_company_name).sum(:fmv_cents)
    chart_data = data.transform_values { |v| v / 100.0 }.sort_by { |_k, v| -v }.first(10).to_h

    if data.size > 10
      others_sum = data.sort_by { |_k, v| -v }[10..-1].sum { |item| item[1] } / 100.0
      chart_data["Others"] = others_sum
    end

    options = { library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:" }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart chart_data, donut: true, title: "Portfolio Allocation (by FMV)", id: "portfolio_allocation_by_company_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Shows the distribution of the fund's current portfolio value (FMV) across different portfolio companies. This helps identify concentration risk.".html_safe
    end

    chart + explanation
  end

  def portfolio_performance_by_company_chart(fund, compact: false)
    apis = fund.aggregate_portfolio_investments.order(fmv_cents: :desc).limit(10)

    data = [
      { name: "Cost", data: apis.map { |api| [api.portfolio_company_name, api.cost_of_remaining_cents / 100.0] } },
      { name: "FMV", data: apis.map { |api| [api.portfolio_company_name, api.fmv_cents / 100.0] } },
      { name: "Realized", data: apis.map { |api| [api.portfolio_company_name, api.sold_amount_cents / 100.0] } }
    ]

    options = {
      library: {
        plotOptions: {
          column: { dataLabels: { enabled: false } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = column_chart data, stacked: false, title: "Investment Performance (Top 10)", id: "portfolio_performance_by_company_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Compares the total cost basis against current Fair Market Value (FMV) and realized proceeds for the top 10 investments, visualizing the value creation for each company.".html_safe
    end

    chart + explanation
  end

  def portfolio_gain_breakdown_chart(fund, compact: false)
    realized = fund.aggregate_portfolio_investments.sum(:gain_cents) / 100.0
    unrealized = fund.aggregate_portfolio_investments.sum(:unrealized_gain_cents) / 100.0

    data = { "Realized Gains" => realized, "Unrealized Gains" => unrealized }.sort_by { |_, v| -v }

    options = {
      library: {
        plotOptions: {
          pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?
    chart = pie_chart data, donut: true, title: "Realized vs Unrealized Gains", id: "portfolio_gain_breakdown_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Breaks down the total portfolio gains into realized (from exits/sales) and unrealized (current paper gains based on latest valuations).".html_safe
    end

    chart + explanation
  end

  def portfolio_instrument_exposure_chart(fund, compact: false)
    data = fund.aggregate_portfolio_investments.joins(:investment_instrument)
               .group("investment_instruments.name").sum(:fmv_cents)
               .transform_values { |v| v / 100.0 }.sort_by { |_k, v| -v }

    options = { library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    } }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Exposure by Instrument Type", id: "portfolio_instrument_exposure_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Shows the allocation of portfolio value across different types of investment instruments (e.g., Equity, Convertible Notes, Debt).".html_safe
    end

    chart + explanation
  end

  def portfolio_income_by_company_chart(fund, compact: false)
    data = fund.aggregate_portfolio_investments.where("portfolio_income_cents > 0")
               .group(:portfolio_company_name).sum(:portfolio_income_cents)
               .transform_values { |v| v / 100.0 }
               .sort_by { |_k, v| -v }.to_h

    options = {
      library: {
        plotOptions: {
          series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = bar_chart data, title: "Portfolio Income by Company", id: "portfolio_income_by_company_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Displays cumulative income (dividends, interest, etc.) received from each portfolio company.".html_safe
    end

    chart + explanation
  end

  def portfolio_irr_chart(fund, compact: false)
    chart = portfolio_last_xirr(fund)
    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "The Internal Rate of Return (IRR) for each portfolio company, representing the annualized yield of the investment.".html_safe
    end
    chart + explanation
  end

  def portfolio_holding_cost_chart(fund, compact: false)
    chart = investment_holding_cost_by_company(fund)
    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Breakdown of the total holding cost (acquisition cost of remaining shares) by portfolio company.".html_safe
    end
    chart + explanation
  end

  def portfolio_bought_amount_chart(fund, compact: false)
    chart = investment_bought_by_company(fund)
    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Total capital invested (bought amount) in each portfolio company since inception.".html_safe
    end
    chart + explanation
  end

  def portfolio_sold_amount_chart(fund, compact: false)
    chart = investment_sold_by_company(fund)
    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Total capital realized (sold amount) from each portfolio company through exits or partial sales.".html_safe
    end
    chart + explanation
  end
end
