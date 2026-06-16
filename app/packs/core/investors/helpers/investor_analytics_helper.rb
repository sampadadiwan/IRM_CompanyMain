module InvestorAnalyticsHelper
  # Renders a donut chart showing the distribution of investors by category.
  # Clickable: Filters the table by category.
  def investor_category_distribution_chart(records)
    data = records.group(:category).count

    pie_chart data, donut: true, title: "Investor Category Distribution", id: "investor_category_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[category_eq]")
    }
  end

  # Renders a donut chart showing the top 10 cities where investors are located.
  # Clickable: Filters the table by city.
  def investor_city_distribution_chart(records)
    data = records.where.not(city: [nil, ""]).group(:city).count.sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Top 10 Cities", id: "investor_city_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[city_eq]")
    }
  end

  # Renders a donut chart showing the distribution of the top 10 tags.
  # Processes the comma-separated tag_list field.
  # Clickable: Filters the table by tag (contains).
  def investor_tag_distribution_chart(records)
    # Extract and count individual tags from the comma-separated tag_list
    all_tags = records.pluck(:tag_list).compact.flat_map { |list| list.split(",").map(&:strip) }.compact_blank
    data = all_tags.tally.sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Top 10 Tags", id: "investor_tag_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[tag_list_cont]")
    }
  end

  # Renders a donut chart showing sector distribution for Portfolio Companies.
  # Clickable: Filters the table by sector (contains).
  def investor_sector_distribution_chart(records)
    # Filter for Portfolio Companies and non-empty sectors
    data = records.where(category: "Portfolio Company").where.not(sector: [nil, ""]).group(:sector).count.sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Sector Distribution (Portfolio Companies)", id: "investor_sector_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[sector_cont]")
    }
  end

  # --- Investor portfolio analytics charts (scoped to a single portfolio company) ---

  # Donut: FMV distribution across the funds that hold this company.
  def investor_allocation_by_fund_chart(apis)
    data = apis.joins(:fund).group("funds.name").sum(:fmv_cents)
               .transform_values { |v| v / 100.0 }.sort_by { |_k, v| -v }.to_h

    options = { library: {
      plotOptions: { pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } } },
      **chart_theme_color
    } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Allocation by Fund (FMV)", id: "investor_allocation_by_fund_chart", **options

    chart + content_tag(:div, "FMV distribution across each fund holding this company — reveals concentration.", class: "mt-3 text-muted small")
  end

  # Column: Cost vs FMV vs Realized per fund for this company.
  def investor_performance_by_fund_chart(apis)
    fund_apis = apis.joins(:fund).order("funds.name")

    grouped = fund_apis.each_with_object({ "Cost" => [], "FMV" => [], "Realized" => [] }) do |api, acc|
      name = api.fund.name
      acc["Cost"]     << [name, api.cost_of_remaining_cents / 100.0]
      acc["FMV"]      << [name, api.fmv_cents / 100.0]
      acc["Realized"] << [name, api.sold_amount_cents / 100.0]
    end

    data = grouped.map { |series_name, points| { name: series_name, data: points } }

    options = { library: { plotOptions: { column: { dataLabels: { enabled: false } } }, **chart_theme_color } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = column_chart data, stacked: false, title: "Performance by Fund (Cost / FMV / Realized)", id: "investor_performance_by_fund_chart", **options

    chart + content_tag(:div, "Compares cost basis, current FMV, and realized proceeds per fund for this company.", class: "mt-3 text-muted small")
  end

  # Donut: Realized vs unrealized gains across all funds for this company.
  def investor_gains_breakdown_chart(apis)
    realized   = apis.sum(:gain_cents) / 100.0
    unrealized = apis.sum(:unrealized_gain_cents) / 100.0

    data = { "Realized Gains" => realized, "Unrealized Gains" => unrealized }.sort_by { |_, v| -v }

    options = { library: {
      plotOptions: { pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } } },
      **chart_theme_color
    } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Realized vs Unrealized Gains", id: "investor_gains_breakdown_chart", **options

    chart + content_tag(:div, "Breaks total gains into realized (exits/sales) and unrealized (paper gains) across all funds.", class: "mt-3 text-muted small")
  end

  # Donut: FMV by investment instrument type for this company.
  def investor_instrument_breakdown_chart(apis)
    data = apis.joins(:investment_instrument).group("investment_instruments.name").sum(:fmv_cents)
               .transform_values { |v| v / 100.0 }.sort_by { |_k, v| -v }.to_h

    options = { library: {
      plotOptions: { pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } } },
      **chart_theme_color
    } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Instrument Breakdown (by FMV)", id: "investor_instrument_breakdown_chart", **options

    chart + content_tag(:div, "Shows how the total investment in this company is split across instrument types (Equity, Debt, Convertible, etc.).", class: "mt-3 text-muted small")
  end

  # Column: Total bought vs sold per fund for this company.
  def investor_bought_vs_sold_by_fund_chart(apis)
    fund_apis = apis.joins(:fund).order("funds.name")

    grouped = fund_apis.each_with_object({ "Invested" => [], "Realized" => [] }) do |api, acc|
      name = api.fund.name
      acc["Invested"]  << [name, api.bought_amount_cents / 100.0]
      acc["Realized"]  << [name, api.sold_amount_cents / 100.0]
    end

    data = grouped.map { |series_name, points| { name: series_name, data: points } }

    options = { library: { **chart_theme_color } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = column_chart data, stacked: false, title: "Invested vs Realized by Fund", id: "investor_bought_vs_sold_by_fund_chart", **options

    chart + content_tag(:div, "Total capital deployed versus capital returned per fund for this company.", class: "mt-3 text-muted small")
  end

  # Bar: Portfolio income (dividends/interest) per fund for this company.
  def investor_income_by_fund_chart(apis)
    data = apis.joins(:fund).where("portfolio_income_cents > 0")
               .group("funds.name").sum(:portfolio_income_cents)
               .transform_values { |v| v / 100.0 }.sort_by { |_k, v| -v }.to_h

    options = { library: {
      plotOptions: { series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } } },
      **chart_theme_color
    } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = bar_chart data, title: "Portfolio Income by Fund", id: "investor_income_by_fund_chart", **options

    chart + content_tag(:div, "Cumulative dividends and interest received from this company, broken down per fund.", class: "mt-3 text-muted small")
  end

  # --- LP flow charts scoped to a single portfolio company (investor) ---

  # Stacked column: X = fund names, series = LP investors (top 10 by commitment).
  # Each bar segment = LP's implied share of this company's FMV in that fund.
  def investor_lp_exposure_by_fund_chart(investor)
    apis = AggregatePortfolioInvestment.where(portfolio_company_id: investor.id)
                                       .where("fmv_cents > 0").includes(:fund).to_a

    return content_tag(:div, "No portfolio FMV data available for this company.", class: "text-muted p-3") if apis.empty?

    # Collect fund IDs and fetch commitments for those funds only
    fund_ids    = apis.map(&:fund_id).uniq
    commitments = CapitalCommitment.where(fund_id: fund_ids)
                                   .where("committed_amount_cents > 0 AND percentage > 0")
                                   .includes(:investor).to_a

    return content_tag(:div, "No LP commitment data found for the funds holding this company.", class: "text-muted p-3") if commitments.empty?

    # Top 10 LP investors across all relevant funds by total committed amount
    top_lps = commitments.group_by { |cc| cc.investor&.investor_name }
                         .reject { |name, _| name.nil? }
                         .transform_values { |ccs| ccs.sum(&:committed_amount_cents) }
                         .sort_by { |_, total| -total }.first(10).map(&:first)

    # Build a lookup: [fund_id, lp_name] => CapitalCommitment
    cc_lookup = commitments.each_with_object({}) do |cc, h|
      name = cc.investor&.investor_name
      h[[cc.fund_id, name]] = cc if name
    end

    data = top_lps.map do |lp_name|
      series_data = apis.to_h do |api|
        cc = cc_lookup[[api.fund_id, lp_name]]
        # LP's implied share of this company's FMV in this fund
        value = cc ? (api.fmv_cents * cc.percentage / 100.0 / 100.0).round(2) : 0
        [api.fund.name, value]
      end
      { name: lp_name, data: series_data }
    end

    options = { library: { **chart_theme_color } }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = column_chart data, stacked: true,
                               title: "LP Implied Exposure by Fund (Top 10 LPs)",
                               id: "investor_lp_exposure_chart_#{investor.id}",
                               **options

    explanation = content_tag(:div, class: "mt-2 text-muted small") do
      "Each bar shows how much of this company's FMV in a fund is attributable to each LP investor, " \
      "calculated as the fund's FMV × the LP's % of that fund's total commitments. " \
      "Top 10 LPs by total commitment shown.".html_safe
    end

    chart + explanation
  end

  # Heatmap data: LP × Fund matrix for a single portfolio company.
  # Cell = LP's implied FMV exposure to this company via that fund.
  # LPs are sorted by total implied FMV descending so the most exposed LPs are at the top.
  # Returns { lp_names:, fund_names:, points: [{ x:, y:, value: }] }.
  def investor_lp_exposure_heatmap_data(investor)
    apis = AggregatePortfolioInvestment.where(portfolio_company_id: investor.id)
                                       .where("fmv_cents > 0").includes(:fund).to_a

    fund_ids    = apis.map(&:fund_id).uniq
    commitments = CapitalCommitment.where(fund_id: fund_ids)
                                   .where("committed_amount_cents > 0 AND percentage > 0")
                                   .includes(:investor).to_a

    # Start with all named LPs
    all_lp_names = commitments.filter_map { |cc| cc.investor&.investor_name }.uniq
    fund_names   = apis.map { |api| api.fund.name }.uniq

    cc_lookup = commitments.each_with_object({}) do |cc, h|
      name = cc.investor&.investor_name
      h[[cc.fund_id, name]] = cc if name
    end

    # Compute all implied FMV values and total per LP
    raw = {}
    all_lp_names.each do |lp_name|
      raw[lp_name] = apis.filter_map do |api|
        cc = cc_lookup[[api.fund_id, lp_name]]
        next unless cc

        fmv = (api.fmv_cents * cc.percentage / 100.0 / 100.0).round(2)
        fmv.positive? ? { fund: api.fund.name, value: fmv } : nil
      end
    end

    # Sort LPs by their total implied FMV and keep top 15
    lp_names = all_lp_names
               .sort_by { |name| -raw[name].sum { |p| p[:value] } }
               .first(15)

    points = lp_names.flat_map.with_index do |lp_name, y|
      raw[lp_name].map { |p| { x: fund_names.index(p[:fund]), y: y, value: p[:value] } }
    end

    { lp_names: lp_names, fund_names: fund_names, points: points }
  end
end
