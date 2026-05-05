module CapitalCommitmentDashboardHelper
  include FundDashboardHelper

  def commitment_deployment_chart(fund, compact: false)
    called = fund.capital_commitments.sum(:call_amount_cents) / 100.0
    total = fund.capital_commitments.sum(:committed_amount_cents) / 100.0
    uncalled = total - called

    data = { "Called" => called, "Uncalled (Dry Powder)" => uncalled }.sort_by { |_, v| -v }

    options = {
      library: {
        plotOptions: {
          pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Capital Called vs Uncalled", id: "commitment_deployment_chart_#{fund.id}", **options

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

    options = {
      library: {
        plotOptions: {
          pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart top_data, donut: true, title: "Investor Concentration (Top #{top_n})", id: "investor_concentration_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "Displays the distribution of total commitments across investors. It helps identify concentration risk by showing which investors hold the largest stakes in the fund.".html_safe
    end

    chart + explanation
  end

  def gp_lp_commitment_chart(fund, compact: false)
    gp_amount = CapitalCommitment.gp(fund.id).sum(:committed_amount_cents) / 100.0
    lp_amount = CapitalCommitment.lp(fund.id).sum(:committed_amount_cents) / 100.0

    data = { "GP" => gp_amount, "LP" => lp_amount }.sort_by { |_, v| -v }

    options = {
      library: {
        plotOptions: {
          pie: { dataLabels: { enabled: true, format: "<b>{point.name}</b>: {point.percentage:.1f} %" } }
        },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }
    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "GP vs LP Commitment", id: "gp_lp_commitment_chart_#{fund.id}", **options

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
    data = fund.capital_commitments.group(:onboarding_completed).count.transform_keys { |k| k ? "Completed" : "Pending" }.sort_by { |_, v| -v }

    options = {
      library: {
      **chart_theme_color
      }
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Onboarding Status", id: "onboarding_status_chart_#{fund.id}", **options

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

    options = {
      library: {
        xAxis: { type: 'datetime' },
        **chart_theme_color
      }, prefix: "#{fund.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = area_chart data, title: "Fundraising Timeline (Cumulative)", id: "fundraising_timeline_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "A cumulative view of commitments over time, showing the velocity of fundraising and the impact of different closing dates.".html_safe
    end

    chart + explanation
  end

  def currency_exposure_chart(fund, compact: false)
    data = fund.capital_commitments.group(:folio_currency).sum(:committed_amount_cents).transform_values { |v| v / 100.0 }.sort_by { |_, v| -v }

    options = {
      library: {
      **chart_theme_color
      }
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    chart = pie_chart data, donut: true, title: "Currency Exposure", id: "currency_exposure_chart_#{fund.id}", **options

    return chart if compact

    explanation = content_tag(:div, class: "mt-3 text-muted small") do
      "For multi-currency funds, this shows the breakdown of commitments by their original denomination, highlighting potential foreign exchange risk.".html_safe
    end

    chart + explanation
  end

  def card2_metrics(cc)
    calcs = CapitalCommitmentCalcs.new(cc, Time.zone.today)
    invested = cc.collected_amount
    committed = cc.committed_amount
    invested_pct = committed.positive? ? (invested / committed * 100).round(1) : 0

    nav_cents = calcs.fmv_cents + calcs.cash_in_hand_cents + calcs.net_current_assets_cents

    # Fallback to sum of account entries if standard NAV calc is <= 0
    # Use reporting_date filter to match the "as of" date of the dashboard
    nav_cents = cc.account_entries.where(reporting_date: ..Time.zone.today).sum(:amount_cents).to_i if nav_cents <= 0

    # Ensure NAV displayed in metrics is not negative
    nav_cents = 0 if nav_cents < 0
    nav = Money.new(nav_cents, cc.currency)

    # Simple comparison for NAV % change (vs previous account entry date)
    prev_ae = cc.account_entries.where(name: "Portfolio FMV").where("reporting_date < ?", Time.zone.today).order(reporting_date: :desc).second
    nav_change_pct = 0
    nav_change_pct = ((nav_cents - prev_ae.amount_cents).to_f / prev_ae.amount_cents * 100).round(1) if prev_ae && prev_ae.amount_cents.positive?

    currency_units = cc.currency == "INR" ? "Crores" : "Millions"

    {
      committed: cc.committed_amount,
      invested: invested,
      invested_pct: invested_pct,
      nav: nav,
      nav_change_pct: nav_change_pct,
      distributed: cc.distribution_amount,
      tvpi: calcs.tvpi.round(2),
      irr: (calcs.xirr * 100).round(2),
      currency_units: currency_units
    }
  end

  def card2_performance_chart(cc, period: "YTD")
    start_date = case period
                 when "3M" then 3.months.ago.to_date.beginning_of_month
                 when "6M" then 6.months.ago.to_date.beginning_of_month
                 when "YTD" then Time.zone.today.beginning_of_year
                 else nil
                 end

    events = Hash.new { |h, k| h[k] = { called: 0.0, distributed: 0.0, nav: 0.0, has_nav: false } }

    cc.capital_remittances.verified.find_each do |r|
      month = r.remittance_date.to_date.beginning_of_month
      events[month][:called] += r.collected_amount_cents / 100.0
    end

    cc.capital_distribution_payments.find_each do |d|
      month = d.payment_date.to_date.beginning_of_month
      events[month][:distributed] += d.net_payable_cents / 100.0
    end

    nav_query = cc.account_entries.where(name: ["Portfolio FMV", "Cash In Hand", "Net Current Assets", "NAV"])
    nav_query = cc.account_entries.where("name LIKE ?", "%Investable Capital%") if nav_query.empty? || nav_query.sum(:amount_cents).zero?
    nav_query = cc.account_entries.where.not(amount_cents: 0) if nav_query.empty? || nav_query.sum(:amount_cents).zero?

    nav_query.find_each do |ae|
      month = ae.reporting_date.to_date.beginning_of_month
      events[month][:nav] += ae.amount_cents / 100.0
      events[month][:has_nav] = true
    end

    all_months = events.keys.dup
    all_months << Time.zone.today.beginning_of_month
    all_months << start_date if start_date

    if all_months.any?
      first_month = all_months.min
      last_month = all_months.max

      current_month = first_month
      while current_month <= last_month
        all_months << current_month
        current_month += 1.month
      end
    end

    all_months.uniq!
    all_months.sort!

    # Pre-calculate AE sum by month for the cumulative NAV fallback
    ae_by_month = cc.account_entries.each_with_object(Hash.new(0)) do |ae, h|
      h[ae.reporting_date.to_date.beginning_of_month] += ae.amount_cents
    end

    cum_called = 0.0
    cum_distributed = 0.0
    cum_ae = 0.0
    last_nav = nil

    # We build the full historical timeline FIRST to ensure cumulative totals
    # are correct even when we slice for 6M or 3M later.
    timeseries = all_months.each_with_object({}) do |month, h|
      if events.key?(month)
        cum_called += events[month][:called]
        cum_distributed += events[month][:distributed]
        last_nav = events[month][:nav] if events[month][:has_nav]
      end

      cum_ae += (ae_by_month[month] / 100.0)

      h[month] = {
        called: cum_called,
        distributed: cum_distributed,
        # Use standard NAV snapshot if available, otherwise fallback to running total of AE
        nav: [last_nav || cum_ae, 0.0].max
      }
    end

    # Apply the period filter AFTER the full historical calculation
    timeseries.select! { |month, _| month >= start_date } if start_date

    # Pass actual Date objects to Chartkick; ensure consistent sorting
    called_data = timeseries.sort.to_h.transform_values { |v| v[:called] }
    distributed_data = timeseries.sort.to_h.transform_values { |v| v[:distributed] }
    nav_data = timeseries.sort.to_h.transform_values { |v| v[:nav] }

    chart_id = "cc_performance_chart_#{cc.id}_#{period}"

    options = {
      library: {
        xAxis: {
          type: 'datetime',
          labels: {
            style: { fontSize: '10px' },
            autoRotation: [-45],
            padding: 5
          },
          dateTimeLabelFormats: {
            month: '%b \'%y',
            year: '%Y'
          }
        },
        **chart_theme_color
      }, prefix: "#{cc.currency}:"
    }

    options[:colors] = pie_chart_colors_from_css if use_custom_colors?

    column_chart [
      { name: "NAV", data: nav_data, library: { type: 'area' } },
      { name: "Called", data: called_data, library: { type: 'column' } },
      { name: "Distributed", data: distributed_data, library: { type: 'column' } }
    ], id: chart_id, **options
  end

  def card2_recent_activity(cc)
    activities = []

    cc.capital_remittances.verified.limit(5).each do |r|
      activities << { type: :remittance, date: r.remittance_date, title: "#{money_to_currency(r.collected_amount)} collected", icon: "ti-arrow-up-right", color: "text-primary" }
    end

    cc.capital_distribution_payments.limit(5).each do |d|
      status = d.completed ? "distributed" : "pending distribution"
      activities << { type: :distribution, date: d.payment_date, title: "#{money_to_currency(d.net_payable)} #{status}", icon: "ti-arrow-down-left", color: "text-success" }
    end

    cc.account_entries.where(name: "Portfolio FMV").limit(5).each do |ae|
      activities << { type: :nav, date: ae.reporting_date, title: "NAV updated", icon: "ti-chart-line", color: "text-info" }
    end

    activities.sort_by { |a| a[:date] }.last(5).reverse
  end

  def card2_attention_items(cc)
    items = []
    # Find the latest capital remittance that is not paid
    latest_pending_remittance = cc.capital_remittances.where.not(status: "Paid").order(remittance_date: :desc).first

    if latest_pending_remittance
      items << {
        type: :due_payment,
        title: "#{money_to_currency(latest_pending_remittance.due_amount)} Due Payment",
        description: "Pay the capital call for #{latest_pending_remittance.capital_call.name} by #{l(latest_pending_remittance.capital_call.due_date)}.",
        action_text: "Pay Now",
        action_url: Rails.application.routes.url_helpers.capital_remittance_path(latest_pending_remittance),
        icon: "ti-wallet",
        color: "bg-danger-subtle text-danger"
      }
    elsif cc.due_amount.positive?
      items << {
        type: :due_payment,
        title: "#{money_to_currency(cc.due_amount)} Due Payment",
        description: "You have an outstanding balance due on your commitment.",
        action_text: "Pay Now",
        action_url: Rails.application.routes.url_helpers.capital_commitment_path(cc),
        icon: "ti-wallet",
        color: "bg-danger-subtle text-danger"
      }
    end

    kyc = cc.investor_kyc
    if kyc && (!kyc.verified || kyc.expired? || !kyc.completed_by_investor)
      items << {
        type: :kyc_update,
        title: "KYC Update Needed",
        description: "Your KYC documents need updating to remain compliant.",
        action_text: "Show Kyc",
        action_url: Rails.application.routes.url_helpers.investor_kyc_path(kyc),
        icon: "ti-id",
        color: "bg-warning-subtle text-warning"
      }
    end
    items
  end
end
