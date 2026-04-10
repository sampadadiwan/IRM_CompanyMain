module CapitalDistributionDashboardHelper
  def distribution_status_chart(fund)
    completed = fund.capital_distributions.sum(:completed_distribution_amount_cents) / 100.0
    gross = fund.capital_distributions.sum(:gross_amount_cents) / 100.0
    pending = gross - completed

    data = { "Completed" => completed, "Pending" => pending }

    chart = pie_chart data, donut: true, title: "Distribution Status", id: "distribution_status_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Shows the ratio of capital successfully distributed to investors versus pending distributions that have been approved but not yet completed.".html_safe
    end

    chart + explanation
  end

  def distribution_history_chart(fund)
    data = fund.capital_distributions.order(:distribution_date).map { |d| [d.title, d.gross_amount_cents / 100.0] }.to_h

    chart = column_chart data, title: "Distribution History", height: "400px", id: "distribution_history_chart_#{fund.id}", library: {
      plotOptions: {
        column: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "A chronological view of all capital distributions made by the fund, visualizing the size and timing of each payout.".html_safe
    end

    chart + explanation
  end

  def distribution_component_breakdown_chart(fund)
    principal = fund.capital_distributions.sum(:cost_of_investment_cents) / 100.0
    income = fund.capital_distributions.sum(:income_cents) / 100.0
    fees = fund.capital_distributions.sum(:fee_cents) / 100.0

    data = { "Principal (Cost)" => principal, "Income (Gains)" => income, "Fees" => fees }

    chart = pie_chart data, donut: true, title: "Distribution Component Breakdown", id: "distribution_component_breakdown_chart_#{fund.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Breaks down the total distributed capital into its components: return of original cost (Principal), realized gains (Income), and any associated fees.".html_safe
    end

    chart + explanation
  end

  def investor_distributions_chart(fund, top_n: 10)
    top_n ||= 10
    data = fund.capital_distribution_payments.completed
               .group(:investor_name)
               .sum(:net_payable_cents)
               .transform_values { |v| v / 100.0 }

    sorted_data = data.sort_by { |_k, v| -v }.first(top_n).to_h

    chart = bar_chart sorted_data, title: "Top #{top_n} Investor Distributions", id: "investor_distributions_chart_#{fund.id}", library: {
      plotOptions: {
        series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Identifies the investors who have received the highest cumulative capital returns from the fund.".html_safe
    end

    chart + explanation
  end

  def cumulative_distributions_chart(fund)
    distributions = fund.capital_distributions.order(:distribution_date)
    cumulative_amount = 0
    data = distributions.each_with_object({}) do |d, hash|
      cumulative_amount += d.gross_amount_cents / 100.0
      hash[d.distribution_date] = cumulative_amount
    end

    chart = area_chart data, title: "Cumulative Distributions Over Time", id: "cumulative_distributions_chart_#{fund.id}", library: {
      xAxis: { type: 'datetime' },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Visualizes the total capital returned to investors over the life of the fund, helping track the J-Curve progression.".html_safe
    end

    chart + explanation
  end
end
