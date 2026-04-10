module CapitalCommitmentDashboardHelper
  def commitment_deployment_chart(fund, compact: false)
    called = fund.capital_commitments.sum(:call_amount_cents) / 100.0
    total = fund.capital_commitments.sum(:committed_amount_cents) / 100.0
    uncalled = total - called

    data = { "Called" => called, "Uncalled (Dry Powder)" => uncalled }

    chart = pie_chart data, donut: true, title: "Capital Called vs Uncalled", id: "commitment_deployment_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "This chart shows the utilization of total committed capital. <strong>Called</strong> represents the amount requested from investors for investments and expenses, while <strong>Uncalled</strong> represents the remaining \"Dry Powder\" available for future calls.".html_safe
    end

    chart + explanation
  end

  def investor_concentration_chart(fund, top_n: 10, compact: false)
    top_n ||= 10
    all_data = fund.capital_commitments.group(:investor_name).sum(:committed_amount_cents).transform_values { |v| v / 100.0 }
    sorted_data = all_data.sort_by { |_k, v| -v }

    top_data = sorted_data.first(top_n).to_h
    if sorted_data.size > top_n
      others_sum = sorted_data[top_n..-1].sum { |_k, v| v }
      top_data["Others"] = others_sum
    end

    chart = pie_chart top_data, donut: true, title: "Investor Concentration (Top #{top_n})", id: "investor_concentration_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Displays the distribution of total commitments across investors. It helps identify concentration risk by showing which investors hold the largest stakes in the fund.".html_safe
    end

    chart + explanation
  end

  def gp_lp_commitment_chart(fund, compact: false)
    gp_amount = CapitalCommitment.gp(fund.id).sum(:committed_amount_cents) / 100.0
    lp_amount = CapitalCommitment.lp(fund.id).sum(:committed_amount_cents) / 100.0

    data = { "GP" => gp_amount, "LP" => lp_amount }

    chart = pie_chart data, donut: true, title: "GP vs LP Commitment", id: "gp_lp_commitment_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Compares the capital committed by the General Partner (GP) versus Limited Partners (LP). This indicates the level of \"skin in the game\" and alignment of interests between the fund manager and investors.".html_safe
    end

    chart + explanation
  end

  def unit_type_distribution_chart(fund, compact: false)
    data = fund.capital_commitments.group(:unit_type).sum(:committed_amount_cents).transform_values { |v| v / 100.0 }

    chart = bar_chart data, title: "Commitment by Unit Type", id: "unit_type_distribution_chart_#{fund.id}", library: {
      plotOptions: {
        series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Shows how commitments are distributed across different share classes or unit types. This is useful for funds with multiple tiers of investors or different fee structures.".html_safe
    end

    chart + explanation
  end

  def onboarding_status_chart(fund, compact: false)
    data = fund.capital_commitments.group(:onboarding_completed).count.transform_keys { |k| k ? "Completed" : "Pending" }

    chart = pie_chart data, donut: true, title: "Onboarding Status", id: "onboarding_status_chart_#{fund.id}", library: {
      **chart_theme_color
    }

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Tracks the operational progress of investor onboarding. <strong>Completed</strong> indicates investors who have finished all documentation and KYC requirements.".html_safe
    end

    chart + explanation
  end

  def fundraising_timeline_chart(fund, compact: false)
    # Cumulative sum of committed amounts over time
    commitments_by_date = fund.capital_commitments.group(:commitment_date).sum(:committed_amount_cents)
    sorted_dates = commitments_by_date.keys.compact.sort

    cumulative_amount = 0
    data = sorted_dates.each_with_object({}) do |date, hash|
      cumulative_amount += commitments_by_date[date] / 100.0
      hash[date] = cumulative_amount
    end

    chart = area_chart data, title: "Fundraising Timeline (Cumulative)", id: "fundraising_timeline_chart_#{fund.id}", library: {
      xAxis: { type: 'datetime' },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "A cumulative view of commitments over time, showing the velocity of fundraising and the impact of different closing dates.".html_safe
    end

    chart + explanation
  end

  def currency_exposure_chart(fund, compact: false)
    data = fund.capital_commitments.group(:folio_currency).sum(:committed_amount_cents).transform_values { |v| v / 100.0 }

    chart = pie_chart data, donut: true, title: "Currency Exposure", id: "currency_exposure_chart_#{fund.id}", library: {
      **chart_theme_color
    }

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "For multi-currency funds, this shows the breakdown of commitments by their original denomination, highlighting potential foreign exchange risk.".html_safe
    end

    chart + explanation
  end
end
