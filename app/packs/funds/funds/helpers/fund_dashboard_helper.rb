module FundDashboardHelper
  # rubocop:disable Metrics/ParameterLists
  def fund_ratios_line_chart(fund, owner_id: nil, owner_type: nil, ratio_names: nil, owner: nil, months: 12, chart_id: "fund_ratios_chart")
    months ||= 12
    ratio_names ||= ["XIRR", "RVPI", "DPI", "TVPI", "Fund Utilization", "Portfolio Value to Cost", "Paid In to Committed Capital", "Quarterly IRR", "IRR", "Value To Cost", "Gross Portfolio IRR"]

    from_date = Time.zone.today - months.months

    # Fetch all fund_ratios in one query
    fund_ratios = if fund.present?
                    fund.fund_ratios
                  else
                    FundRatio.includes(:fund).all # Include fund to group properly
                  end

    fund_ratios = fund_ratios.where(owner_id: owner_id, owner_type: owner_type) if owner_id.present? && owner_type.present?
    fund_ratios = fund_ratios.where(name: ratio_names, end_date: from_date..)
                             .order(:name, :end_date)

    fund_ratios = fund_ratios.where(owner: owner) if owner.present?

    # Group by fund name and ratio name
    ratios_data = fund_ratios.group_by { |fr| [fr.fund.name, fr.name] }.transform_values do |ratios|
      ratios.group_by { |v| v.end_date.strftime("%m/%Y") }
            .map { |date, vals| [date, vals[-1].value&.round(2)] } # Take last value for the month
            .sort_by { |date, _| Date.strptime(date, "%m/%Y") }
    end

    # Prepare the series data for the chart
    series = ratios_data.map do |(fund_name, ratio_name), data|
      {
        name: "#{fund_name} - #{ratio_name}",
        data: data
      }
    end

    # Plot the chart with multiple series
    line_chart series, id: chart_id, library: {
      plotOptions: {
        series: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end
  # rubocop:enable Metrics/ParameterLists

  def account_entries_line_chart(fund, entry_types: %w[Expense Fee], months: 12)
    from_date = Time.zone.today - months.months
    # Retrieve and group data by entry_type and date
    entries_by_type = entry_types.each_with_object({}) do |type, hash|
      account_entries = fund.account_entries
                            .not_cumulative
                            .where(entry_type: type).where.not(capital_commitment_id: nil)
                            .where(reporting_date: from_date..)

      grouped_entries = account_entries.group_by { |entry| entry.reporting_date.strftime("%m/%Y") }
                                       .map { |date, entries| [date, entries.sum(&:amount_cents) / 100] }
                                       .sort_by { |date, _| Date.strptime(date, "%m/%Y") }

      hash[type] = grouped_entries
    end

    # Prepare the series for the chart
    series = entries_by_type.map do |entry_type, data|
      {
        name: entry_type,
        data:
      }
    end

    # Plot the line chart with multiple series
    line_chart series, library: {
      plotOptions: {
        series: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      xAxis: { title: { text: "Reporting Date" } },
      yAxis: { title: { text: "Amount" } },
      **chart_theme_color
    }
  end

  def fund_cashflows(fund, months: 36)
    from_date = Time.zone.today - months.months

    # Fetch data
    capital_calls = fund.capital_calls.where(call_date: from_date..)
    capital_distributions = fund.capital_distributions.where(distribution_date: from_date..)
    portfolio_investments = fund.portfolio_investments.where(investment_date: from_date..)
    account_entries = fund.account_entries.not_cumulative.where.not(capital_commitment_id: nil).where(entry_type: %w[Expense Fee], reporting_date: from_date..)

    # Group and sum data by quarter
    data = {
      "Capital Calls" => capital_calls,
      "Capital Distributions" => capital_distributions,
      "Portfolio Investments" => portfolio_investments,
      "Expenses" => account_entries
    }.transform_values do |records|
      records.group_by { |record| "Q#{quarter(record_date(record))}-#{record_date(record).strftime('%y')}" }
             .transform_values { |entries| entries.sum { |e| amount_cents(e) / 100.0 } }
    end

    # Get all quarters and sort them
    all_quarters = data.values.flat_map(&:keys).uniq.sort_by do |q|
      quarter_part, year_part = q.split("-")
      [year_part.to_i, quarter_part.delete_prefix("Q").to_i]
    end

    # Prepare chart data
    chart_data = data.map do |name, records|
      {
        name: name,
        data: all_quarters.map { |quarter| [quarter, records[quarter] || 0] }
      }
    end

    Rails.logger.debug chart_data

    # Plot the chart
    line_chart chart_data, library: {
      plotOptions: {
        series: {
          dataLabels: { enabled: true, format: "{point.y:,.2f}" }
        }
      },
      xAxis: { type: 'category', title: { text: 'Quarters' } },
      yAxis: { title: { text: 'Amount (in currency)' } }
    }, prefix: "#{fund.currency}:"
  end

  private

  def record_date(record)
    record.try(:call_date) || record.try(:distribution_date) || record.try(:investment_date) || record.try(:reporting_date)
  end

  def amount_cents(record)
    record.try(:collected_amount_cents) || record.try(:gross_amount_cents) || record.try(:amount_cents)
  end
end
