module FundDashboardHelper
  def fund_ratios_line_chart(fund, owner_id: nil, owner_type: nil, ratio_names: nil, owner: nil, months: 12)
    ratio_names ||= ["XIRR", "RVPI", "DPI", "TVPI", "Fund Utilization", "Portfolio Value to Cost", "Paid In to Committed Capital", "Quarterly IRR", "IRR", "Value To Cost", "Gross Portfolio IRR"]

    # Initialize an empty hash to store processed data for each ratio
    from_date = Time.zone.today - months.months
    # Fetch all fund_ratios in one query
    fund_ratios = if fund.present?
                    fund.fund_ratios
                  else
                    FundRatio.all
                  end

    fund_ratios = fund_ratios.where(owner_id: owner_id, owner_type: owner_type) if owner_id.present? && owner_type.present?
    fund_ratios = fund_ratios.where(name: ratio_names, end_date: from_date..)
                             .order(:name, :end_date)

    # Apply owner filter if provided
    fund_ratios = fund_ratios.where(owner: owner) if owner.present?

    # Process data: Group by ratio name and format it
    ratios_data = fund_ratios.group_by(&:name).transform_values do |ratios|
      ratios.group_by { |v| v.end_date.strftime("%m/%Y") }
            .map { |date, vals| [date, vals[-1].value.round(2)] }
            .sort_by { |date, _| Date.strptime(date, "%m/%Y") }
    end

    # Prepare the series data for the chart
    series = ratios_data.map do |name, data|
      {
        name:,
        data:
      }
    end

    # Plot the chart with multiple series
    line_chart series, library: {
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

  def account_entries_line_chart(fund, entry_types: %w[Expense Fee], months: 12)
    from_date = Time.zone.today - months.months
    # Retrieve and group data by entry_type and date
    entries_by_type = entry_types.each_with_object({}) do |type, hash|
      account_entries = fund.account_entries
                            .not_cumulative
                            .where(entry_type: type)
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

  def fund_cashflows(fund, months: 56)
    from_date = Time.zone.today - months.months
    # Get the calls for last
    capital_calls = fund.capital_calls.where(call_date: from_date..)
    # Get the PIs
    portfolio_investments = fund.portfolio_investments.where(investment_date: from_date..)
    # Get the expenses
    acccount_entries = fund.account_entries.not_cumulative.where(entry_type: %w[Expense Fee]).where(reporting_date: from_date..)

    # Grouping and summing capital_calls by quarter
    capital_calls_data = capital_calls.group_by { |cc| "Q#{quarter(cc.due_date)}" }
                                      .transform_values { |entries| entries.sum { |e| e.collected_amount_cents / 100.0 } }

    # Grouping and summing portfolio_investments by quarter
    portfolio_investments_data = portfolio_investments.group_by { |pi| "Q#{quarter(pi.investment_date)}" }
                                                      .transform_values { |entries| entries.sum { |e| e.amount_cents / 100.0 } }

    acccount_entries_data = acccount_entries.group_by { |ae| "Q#{quarter(ae.reporting_date)}" }
                                            .transform_values { |entries| entries.sum { |e| e.amount_cents / 100.0 } }

    # Combining data for stacking
    all_quarters = (capital_calls_data.keys + portfolio_investments_data.keys + acccount_entries_data.keys).uniq.sort

    capital_calls_chart_data = all_quarters.map do |quarter|
      [quarter, capital_calls_data[quarter] || 0]
    end

    portfolio_investments_chart_data = all_quarters.map do |quarter|
      [quarter, portfolio_investments_data[quarter] || 0]
    end

    acccount_entries_chart_data = all_quarters.map do |quarter|
      [quarter, acccount_entries_data[quarter] || 0]
    end

    chart_data = [
      {
        name: "Capital Calls",
        data: capital_calls_chart_data
      },
      {
        name: "Portfolio Investments",
        data: portfolio_investments_chart_data
      },
      {
        name: "Expenses",
        data: acccount_entries_chart_data
      }
    ]

    Rails.logger.debug chart_data

    column_chart chart_data, library: {
      chart: {
        type: 'column'
      },
      plotOptions: {
        column: {
          stacking: 'normal', # Enables stacking
          dataLabels: { enabled: true, format: "{point.y:,.2f}" }
        }
      },
      xAxis: {
        type: 'category', # Treat x-values as categories (e.g., Q1, Q2, Q3)
        title: { text: 'Quarters' }
      },
      yAxis: {
        title: { text: 'Amount (in currency)' }
      }
    }, prefix: "#{fund.currency}:"
  end
end
