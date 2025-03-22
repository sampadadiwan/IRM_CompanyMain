module FundDashboardHelper
  def fund_ratios_line_chart(fund, owner_id: nil, owner_type: nil, ratio_names: nil, owner: nil, months: 12)
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

  def fund_cashflows(fund, months: 36)
    from_date = Time.zone.today - months.months
    # Get the calls for last
    capital_calls = fund.capital_calls.where(call_date: from_date..)
    capital_distributions = fund.capital_distributions.where(distribution_date: from_date..)
    # Get the PIs
    portfolio_investments = fund.portfolio_investments.where(investment_date: from_date..)
    # Get the expenses
    acccount_entries = fund.account_entries.not_cumulative.where(entry_type: %w[Expense Fee]).where(reporting_date: from_date..)

    # Grouping and summing capital_calls by quarter
    capital_calls_data = capital_calls.group_by do |cc|
      "Q#{quarter(cc.due_date)}-#{cc.due_date.strftime('%y')}"
    end
      .transform_values { |entries| entries.sum { |e| e.collected_amount_cents / 100.0 } }

    capital_distributions_data = capital_distributions.group_by do |cc|
      "Q#{quarter(cc.distribution_date)}-#{cc.distribution_date.strftime('%y')}"
    end
      .transform_values { |entries| entries.sum { |e| e.gross_amount_cents / 100.0 } }

    # Grouping and summing portfolio_investments by quarter
    portfolio_investments_data = portfolio_investments.group_by do |pi|
      "Q#{quarter(pi.investment_date)}-#{pi.investment_date.strftime('%y')}"
    end
        .transform_values { |entries| entries.sum { |e| e.amount_cents / 100.0 } }

    acccount_entries_data = acccount_entries.group_by do |ae|
      "Q#{quarter(ae.reporting_date)}-#{ae.reporting_date.strftime('%y')}"
    end
      .transform_values { |entries| entries.sum { |e| e.amount_cents / 100.0 } }

    # Combining data for stacking
    # q.split("-") splits strings like "Q4-22" into ["Q4", "22"].
    # quarter_part.delete_prefix("Q").to_i gets the numeric quarter.
    # We sort using [year_number, quarter_number], so it’s first by year, then by quarter.
    all_quarters = (capital_calls_data.keys + capital_distributions_data.keys + portfolio_investments_data.keys + acccount_entries_data.keys).uniq.sort_by do |q|
      quarter_part, year_part = q.split("-")
      quarter_number = quarter_part.delete_prefix("Q").to_i
      year_number = year_part.to_i
      [year_number, quarter_number] # sort by year first, then quarter
    end

    capital_calls_chart_data = all_quarters.map do |quarter|
      [quarter, capital_calls_data[quarter] || 0]
    end

    capital_distributions_chart_data = all_quarters.map do |quarter|
      [quarter, capital_distributions_data[quarter] || 0]
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
        name: "Capital Distributions",
        data: capital_distributions_chart_data
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
