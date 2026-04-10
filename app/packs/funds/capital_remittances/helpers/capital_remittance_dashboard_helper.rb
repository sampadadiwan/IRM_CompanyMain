module CapitalRemittanceDashboardHelper
  def remittance_status_chart(owner)
    remittances = owner_remittances(owner)
    data = remittances.group(:status).count

    chart = pie_chart data, donut: true, title: "Remittance Status", id: "remittance_status_chart_#{owner.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Breakdown of remittances by their current status (Paid, Pending, Overdue, Overpaid).".html_safe
    end

    chart + explanation
  end

  def remittance_collection_progress_chart(owner)
    remittances = owner_remittances(owner)
    collected = remittances.sum(:collected_amount_cents) / 100.0
    called = remittances.sum("call_amount_cents + other_fee_cents") / 100.0
    outstanding = called - collected

    data = { "Collected" => collected, "Outstanding" => outstanding }

    chart = pie_chart data, donut: true, title: "Collection Progress", id: "remittance_collection_progress_chart_#{owner.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{owner_currency(owner)}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Total capital collected versus outstanding dues for the selected scope.".html_safe
    end

    chart + explanation
  end

  def top_delinquent_investors_chart(owner, top_n: 10)
    top_n ||= 10
    remittances = owner_remittances(owner).where(status: %w[Pending Overdue])

    data = remittances.group(:investor_name)
                      .sum("call_amount_cents + other_fee_cents - collected_amount_cents")
                      .transform_values { |v| v / 100.0 }

    sorted_data = data.sort_by { |_k, v| -v }.first(top_n).to_h

    chart = bar_chart sorted_data, title: "Top #{top_n} Outstanding Dues", id: "top_delinquent_investors_chart_#{owner.id}", library: {
      plotOptions: {
        series: { dataLabels: { enabled: true, format: "{point.y:,.0f}" } }
      },
      **chart_theme_color
    }, prefix: "#{owner_currency(owner)}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Investors with the highest unpaid balances in this scope.".html_safe
    end

    chart + explanation
  end

  def remittance_fee_breakdown_chart(owner)
    remittances = owner_remittances(owner)
    principal = remittances.sum(:investment_amount_cents) / 100.0
    capital_fees = remittances.sum(:capital_fee_cents) / 100.0
    other_fees = remittances.sum(:other_fee_cents) / 100.0

    data = { "Investment" => principal, "Capital Fees" => capital_fees, "Other Fees" => other_fees }

    chart = pie_chart data, donut: true, title: "Fee vs Investment Breakdown", id: "remittance_fee_breakdown_chart_#{owner.id}", library: {
      plotOptions: {
        pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
      },
      **chart_theme_color
    }, prefix: "#{owner_currency(owner)}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Split between actual investment capital and various fees within the remittances.".html_safe
    end

    chart + explanation
  end

  def remittance_payment_timeline_chart(owner)
    remittances = owner_remittances(owner)
    # This is tricky because payments are in a separate table
    payments = CapitalRemittancePayment.where(capital_remittance_id: remittances.select(:id)).order(:payment_date)

    cumulative_amount = 0
    data = payments.each_with_object({}) do |p, hash|
      cumulative_amount += p.amount_cents / 100.0
      hash[p.payment_date] = cumulative_amount
    end

    chart = area_chart data, title: "Cumulative Collection Timeline", id: "remittance_payment_timeline_chart_#{owner.id}", library: {
      xAxis: { type: 'datetime' },
      **chart_theme_color
    }, prefix: "#{owner_currency(owner)}:"

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Visualizes the velocity of capital inflows over time.".html_safe
    end

    chart + explanation
  end

  private

  def owner_remittances(owner)
    if owner.is_a?(Fund)
      owner.capital_remittances
    elsif owner.is_a?(CapitalCall)
      owner.capital_remittances
    else
      CapitalRemittance.none
    end
  end

  def owner_currency(owner)
    owner.is_a?(Fund) ? owner.currency : owner.fund.currency
  end
end
