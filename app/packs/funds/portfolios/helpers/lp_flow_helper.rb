module LpFlowHelper
  # Stacked column chart: each series is one LP, each category is a portfolio company.
  # Cell value = company's FMV × LP's % of the fund.
  # Limits to top 10 LPs (by commitment) and top 15 companies (by FMV) to keep it readable.
  def lp_exposure_by_company_chart(fund)
    commitments = fund.capital_commitments.includes(:investor)
                      .where("committed_amount_cents > 0 AND percentage > 0")
                      .sort_by { |cc| -cc.committed_amount_cents }
                      .first(10)
    apis        = fund.aggregate_portfolio_investments.where("fmv_cents > 0")
                      .order(fmv_cents: :desc).limit(15).to_a

    return content_tag(:div, "No LP or portfolio data available yet.", class: "text-muted p-3") if commitments.empty? || apis.empty?

    data = commitments.map do |cc|
      lp_name     = cc.investor&.investor_name || "Unknown"
      series_data = apis.map do |api|
        # LP's implied share of this company's FMV
        [api.portfolio_company_name, (api.fmv_cents * cc.percentage / 100.0 / 100.0).round(2)]
      end.to_h
      { name: lp_name, data: series_data }
    end

    options = { library: { **chart_theme_color }, prefix: "#{fund.currency}:" }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = column_chart data, stacked: true,
                               title: "LP Implied Exposure by Portfolio Company (Top 10 LPs)",
                               id: "lp_exposure_chart_#{fund.id}",
                               **options

    explanation = content_tag(:div, class: "mt-2 text-muted small") do
      "Each bar shows how much of a portfolio company's current FMV is attributable to each LP investor, " \
      "calculated as the company's FMV × the LP's percentage share of total fund commitments. " \
      "Taller bars = higher implied exposure. Top 10 LPs by commitment shown.".html_safe
    end

    chart + explanation
  end

  # Heatmap data: each cell is an LP's implied FMV exposure to a portfolio company.
  # Implied FMV = company FMV in fund × (LP committed / total committed).
  # Returns { lp_names: [], company_names: [], points: [{ x:, y:, value: }] }.
  def lp_flow_heatmap_data(fund)
    commitments   = fund.capital_commitments.includes(:investor)
                        .where("committed_amount_cents > 0 AND percentage > 0").to_a
    apis          = fund.aggregate_portfolio_investments.where("fmv_cents > 0").to_a

    company_names = apis.map(&:portfolio_company_name).uniq
    all_lp_names  = commitments.filter_map { |cc| cc.investor&.investor_name }.uniq

    cc_lookup = commitments.each_with_object({}) do |cc, h|
      name = cc.investor&.investor_name
      h[name] = cc if name
    end

    # Compute raw exposures and total per LP, then sort descending and cap at 15
    raw = {}
    all_lp_names.each do |lp_name|
      cc = cc_lookup[lp_name]
      next unless cc
      raw[lp_name] = apis.filter_map do |api|
        fmv = (api.fmv_cents * cc.percentage / 100.0 / 100.0).round(2)
        fmv > 0 ? { company: api.portfolio_company_name, value: fmv } : nil
      end
    end

    lp_names = all_lp_names
                 .sort_by { |name| -(raw[name]&.sum { |p| p[:value] } || 0) }
                 .first(15)

    points = lp_names.flat_map.with_index do |lp_name, y|
      (raw[lp_name] || []).map { |p| { x: company_names.index(p[:company]), y: y, value: p[:value] } }
    end

    { lp_names: lp_names, company_names: company_names, points: points }
  end
end
