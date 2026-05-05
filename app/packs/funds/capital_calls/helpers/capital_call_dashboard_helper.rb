module CapitalCallDashboardHelper
  def call_collection_status_chart(fund)
    collected = fund.capital_calls.sum(:collected_amount_cents) / 100.0
    total_called = fund.capital_calls.sum(:call_amount_cents) / 100.0
    outstanding = total_called - collected

    data = { "Collected" => collected, "Outstanding" => outstanding }.sort_by { |_, v| -v }

    chart = pie_chart data, donut: true, title: "Overall Collection Status", id: "call_collection_status_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Shows the ratio of capital successfully collected versus outstanding dues across all capital calls in the fund's history.".html_safe
    end

    chart + explanation
  end

  def call_history_chart(fund)
    data = fund.capital_calls.order(:call_date).map { |c| [c.name, c.call_amount_cents / 100.0] }.to_h

    chart = column_chart data, title: "Capital Call History", height: "400px", id: "call_history_chart_#{fund.id}", library: {
      plotOptions: {
        column: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "A chronological view of all capital calls made by the fund, visualizing the size and timing of each request.".html_safe
    end

    chart + explanation
  end

  def call_collection_efficiency_chart(fund)
    calls = fund.capital_calls.order(:call_date).last(10)

    data = [
      { name: "Called", data: calls.map { |c| [c.name, c.call_amount_cents / 100.0] } },
      { name: "Collected", data: calls.map { |c| [c.name, c.collected_amount_cents / 100.0] } }
    ]

    chart = column_chart data, title: "Collection Efficiency (Last 10 Calls)", height: "400px", id: "call_collection_efficiency_chart_#{fund.id}", library: {
      plotOptions: {
        column: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Compares the amount requested versus the amount actually received for the most recent calls, highlighting any collection delays.".html_safe
    end

    chart + explanation
  end

  def call_fee_breakdown_chart(fund)
    capital_fees = fund.capital_calls.sum(:capital_fee_cents) / 100.0
    other_fees = fund.capital_calls.sum(:other_fee_cents) / 100.0
    total_called = fund.capital_calls.sum(:call_amount_cents) / 100.0
    investment_amount = total_called - capital_fees

    data = { "Investment" => investment_amount, "Capital Fees" => capital_fees, "Other Fees" => other_fees }.sort_by { |_, v| -v }

    chart = pie_chart data, donut: true, title: "Fee vs Investment Breakdown", id: "call_fee_breakdown_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Breaks down the total called capital into its components: actual investment capital, capital-linked fees, and other administrative fees.".html_safe
    end

    chart + explanation
  end

  def investor_call_dues_chart(fund, top_n: 10)
    top_n ||= 10
    dues = fund.capital_remittances.where(status: %w[Pending Overdue])
               .group(:investor_name)
               .sum("call_amount_cents + other_fee_cents - collected_amount_cents")
               .transform_values { |v| v / 100.0 }

    sorted_dues = dues.sort_by { |_k, v| -v }.first(top_n).to_h

    chart = bar_chart sorted_dues, title: "Top #{top_n} Investor Dues", id: "investor_call_dues_chart_#{fund.id}", library: {
      plotOptions: {
        series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Identifies the investors with the highest outstanding balances across all active capital calls, facilitating targeted follow-ups.".html_safe
    end

    chart + explanation
  end
end
