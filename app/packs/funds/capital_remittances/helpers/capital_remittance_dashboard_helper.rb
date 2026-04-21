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

  def remittance_payment_timeline_chart(owner, chart_type: nil)
    chart_type ||= :area
    remittances = owner_remittances(owner)

    # Initial historical amount (e.g. from previous calls not in the current scope)
    # We want a starting point if we are looking at a subset, but usually 'owner' is a Fund or CapitalCall.
    # If it's a Fund, we want the total cumulative from the beginning.
    # If it's a CapitalCall, maybe we only want that call's payments?
    # The existing owner_remittances(owner) handles the scoping.

    payments = CapitalRemittancePayment.where(capital_remittance_id: remittances.select(:id))
                                       .where("amount_cents > 0")
                                       .order(:payment_date)

    # Sum payments by date
    daily_totals = payments.group(:payment_date).sum(:amount_cents)

    # To show a continuous cumulative chart even on days with no payments, 
    # we need to fill in the gaps if we want a "step" look, 
    # but Highcharts with an area/line chart usually handles the interpolation.
    
    cumulative_amount = 0
    sorted_dates = daily_totals.keys.compact.sort
    
    data = sorted_dates.each_with_object([]) do |date, arr|
      cumulative_amount += daily_totals[date] / 100.0
      arr << [date, cumulative_amount]
    end

    # Handle Chart Type Mapping
    chart_method = case chart_type.to_s
                   when "line" then :line_chart
                   when "spline" then :line_chart
                   when "bar" then :column_chart
                   when "area" then :area_chart
                   else :area_chart
                   end

    options = {
      title: "Cumulative Collection Timeline",
      id: "remittance_payment_timeline_chart_#{owner.id}",
      library: {
        xAxis: { type: "datetime" },
        plotOptions: {
          series: {
            marker: { enabled: true }
          }
        },
        **chart_theme_color
      },
      prefix: "#{owner_currency(owner)}:"
    }
    options[:curve] = true if chart_type.to_s == "spline"

    # For cumulative charts, we want to see the progress as a step-up when a payment occurs
    if %w[area line spline bar].include?(chart_type.to_s)
      options[:library][:plotOptions][:series][:step] = 'left'
    end

    chart = send(chart_method, data, **options)

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
