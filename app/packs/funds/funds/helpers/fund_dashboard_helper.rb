module FundDashboardHelper
  def fund_ratios_line_chart(fund, args: {}, owner_id: nil, owner_type: nil, ratio_names: nil, owner: nil, months: 24, fund_ratios: [], chart_id: "fund_ratios_chart", hide_fund_name: false, chart_type: nil)
    months ||= 24
    chart_type ||= args[:chart_type] || "line"
    ratio_names ||= ["XIRR", "RVPI", "DPI", "TVPI", "Fund Utilization", "Portfolio Value to Cost", "Paid In to Committed Capital", "Quarterly IRR", "IRR", "Value To Cost", "Gross Portfolio IRR"]

    # we only fetch ratios if not passed as argument, this is to optimize in cases where we already have the ratios fetched for list and just want to render the chart with them
    if fund_ratios.blank?
      if owner.present?
        owner_id ||= owner.id
        owner_type ||= owner.class.name
      end

      # This will add but not override attrs if they are already present in args
      args = { fund_id: fund&.id, owner_id:, owner_type:, name: ratio_names, months: months }.merge(args)
      result = FundRatioList.call(current_user, args) { |relation| policy_scope(relation) }
      fund_ratios = result.fund_ratios
    end

    from_date = months.is_a?(Numeric) ? Time.zone.today - months.months : nil
    fund_ratios = fund_ratios.where(end_date: from_date..) if from_date
    fund_ratios = fund_ratios.order(:name, :end_date)

    # Get all unique dates across all ratios to ensure consistent X-axis sorting
    all_dates = fund_ratios.map { |fr| fr.end_date.beginning_of_month }.uniq.sort

    # Group by commitment name (when owner is a commitment) or fund name, plus ratio name
    ratios_data = fund_ratios.group_by do |fr|
      label = fr.capital_commitment.present? ? fr.capital_commitment.to_s : fr.fund.name
      [label, fr.name]
    end.transform_values do |ratios|
      ratios_by_date = ratios.group_by { |v| v.end_date.beginning_of_month }
      all_dates.map do |date|
        vals = ratios_by_date[date]
        [date.strftime("%b %y"), vals ? vals[-1].value&.round(2) : nil]
      end
    end

    # Prepare the series data for the chart
    series = ratios_data.map do |(fund_name, ratio_name), data|
      series_name =
        if fund_name.nil? || hide_fund_name
          ratio_name
        else
          "#{fund_name} - #{ratio_name}"
        end

      {
        name: series_name,
        data: data
      }
    end

    line_chart_options = create_line_chart_options(args)

    chart_method = case chart_type.to_s
                   when "bar"    then :column_chart
                   when "area"   then :area_chart
                   else               :line_chart
                   end

    # Plot the chart with multiple series
    send(chart_method, series, id: chart_id, discrete: true, library: line_chart_options)
  end

  def create_line_chart_options(args)
    decimals = args[:decimals].present? ? args[:decimals].to_i : 2
    label_format = "{point.y:,.#{decimals}f}"

    line_chart_options = {
      plotOptions: {
        series: {
          dataLabels: {
            enabled: true,
            format: label_format
          }
        }
      },
      **chart_theme_color
    }

    line_chart_options[:xAxis] = (line_chart_options[:xAxis] || {}).merge(type: 'category', tickmarkPlacement: 'on')

    line_chart_options[:yAxis] = { title: { text: nil }, labels: { enabled: false } } if args[:show_y_axis].to_s.downcase == "false"
    line_chart_options[:legend] = { enabled: false } if args[:show_legend].to_s.downcase == "false"

    line_chart_options
  end

  def account_entries_line_chart(fund, entry_types: %w[Expense Fee], months: 12, use_entries: 'folio_only')
    months = months.to_i if months.is_a?(String)

    from_date = Time.zone.today - months.months
    # Retrieve and group data by entry_type and date
    entries_by_type = entry_types.each_with_object({}) do |type, hash|
      account_entries = fund.account_entries
                            .not_cumulative
                            .where(entry_type: type)

      account_entries = if use_entries.to_s == 'fund_only'
                          account_entries.where(capital_commitment_id: nil)
                        else
                          account_entries.where.not(capital_commitment_id: nil)
                        end

      account_entries = account_entries.where(reporting_date: from_date..)

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

  def fund_cashflows(fund, months: 36, series: nil, chart_type: nil, aggregate_by: nil, cumulative: false)
    months ||= 36
    aggregate_by ||= "year"
    from_date = Time.zone.today - months.months

    # Fetch data
    capital_calls = fund.capital_calls.where(call_date: from_date..)
    capital_distributions = fund.capital_distributions.where(distribution_date: from_date..)
    portfolio_investments = fund.portfolio_investments.where(investment_date: from_date..)
    account_entries = fund.account_entries
                          .not_cumulative
                          .where.not(capital_commitment_id: nil)
                          .where(entry_type: %w[Expense Fee], reporting_date: from_date..)

    # Grouping logic
    group_fn = case aggregate_by.to_s
               when "month" then ->(d) { d.end_of_month }
               when "year"  then ->(d) { d.end_of_year }
               else              ->(d) { d.end_of_quarter }
               end

    # Group and sum data
    data = {
      "Collected Capital" => capital_calls.group_by { |record| group_fn.call(record_date(record)) }
                                          .transform_values { |entries| entries.sum { |e| (e.try(:collected_amount_cents) || 0) / 100.0 } },

      "Capital Distributions" => capital_distributions.group_by { |record| group_fn.call(record_date(record)) }
                                                      .transform_values { |entries| entries.sum { |e| amount_cents(e) / 100.0 } },

      "Portfolio Investments" => portfolio_investments.group_by { |record| group_fn.call(record_date(record)) }
                                                      .transform_values { |entries| entries.sum { |e| amount_cents(e) / 100.0 } },

      "Expenses" => account_entries.group_by { |record| group_fn.call(record_date(record)) }
                                   .transform_values { |entries| entries.sum { |e| amount_cents(e) / 100.0 } }
    }

    # Get all period dates and sort chronologically
    all_periods = data.values.flat_map(&:keys).uniq.compact.sort

    # Filter to requested series if specified
    allowed = Array(series).map { |x| x.to_s.strip } if series.present?
    data = data.select { |name, _| allowed.nil? || allowed.any? { |s| name.downcase.include?(s.downcase) } }

    # Prepare chart data
    chart_data = data.map do |name, records|
      running_total = 0

      {
        name: cumulative ? "#{name} - Cumulative" : name,
        data: all_periods.map do |period|
          label = case aggregate_by.to_s
                  when "month", "quarter" then period.strftime("%m/%y")
                  when "year"             then period.year.to_s
                  else                         period.to_s
                  end

          amount = records[period] || 0
          value = if cumulative
                    running_total += amount
                  else
                    amount
                  end

          [label, value]
        end
      }
    end

    Rails.logger.debug chart_data

    chart_method = case chart_type.to_s
                   when "bar"  then :column_chart
                   when "area" then :area_chart
                   else             :line_chart
                   end

    library_options = {
      plotOptions: {
        series: {
          dataLabels: { enabled: true, format: "{point.y:,.2f}" }
        }
      },
      yAxis: { title: { text: "Amount (in currency)" } },
      **chart_theme_color
    }

    # Plot the chart
    options = { library: library_options, prefix: "#{fund.currency}:" }
    send(chart_method, chart_data, **options)
  end

  # Renders a chart grouped by metric (name) with scenarios as series.
  # This aligns with the `_index_scenarios` table which picks the latest value
  # per (metric, scenario). X-axis will be metric names (base name without currency)
  # and each scenario will be a series of values.
  def fund_ratios_line_chart_by_scenario(fund = nil, args: {}, fund_ratios: [], grouped_ratios: nil, chart_id: "fund_ratios_by_scenario_chart", chart_type: nil)
    if grouped_ratios.present?
      metrics = grouped_ratios.keys
      scenarios = metrics.any? ? grouped_ratios[metrics.first].keys : []
    else
      if fund_ratios.blank?
        args = { fund_id: fund&.id, name: args[:ratio_names], months: args[:months] }.merge(args)
        result = FundRatioList.call(current_user, args) { |relation| policy_scope(relation) }
        fund_ratios = result.fund_ratios
      end

      metrics = fund_ratios.map(&:name).uniq

      if args[:scenarios].present? && args[:scenarios] != "true"
        scenarios = args[:scenarios].to_s.split(",").map(&:strip)
      else
        scenarios = fund_ratios.map(&:scenario).uniq

        if scenarios.include?("Default")
          scenarios.delete("Default")
          scenarios.unshift("Default")
        end
      end

      grouped_ratios = {}

      metrics.each do |metric|
        grouped_ratios[metric] = {}

        scenarios.each do |scenario|
          grouped_ratios[metric][scenario] =
            fund_ratios
            .select { |fr| fr.name == metric && fr.scenario == scenario }
            .max_by(&:end_date)
        end
      end
    end

    categories = scenarios.map { |scenario| scenario == "Default" ? "Actual" : scenario }

    series = metrics.map do |metric|
      display_metric_name = metric.gsub(/\([A-Z]{3}\)$/, "").strip

      values = scenarios.map do |scenario|
        fr = grouped_ratios.dig(metric, scenario)
        fr&.value&.round(2)
      end

      {
        name: display_metric_name,
        data: categories.zip(values)
      }
    end

    chart_method = case chart_type.to_s
                   when "bar" then :column_chart
                   when "area" then :area_chart
                   else :line_chart
                   end

    chart_options = create_line_chart_options(args)

    # Important: do NOT set xAxis categories here.
    # Chartkick uses the [["Actual", 1.0], ["MOIC", 2.2]] data pairs directly.

    send(
      chart_method,
      series,
      id: chart_id,
      discrete: true,
      library: chart_options
    )
  end

  private

  def record_date(record)
    record.try(:call_date) || record.try(:distribution_date) || record.try(:investment_date) || record.try(:reporting_date)
  end

  def amount_cents(record)
    record.try(:collected_amount_cents) || record.try(:gross_amount_cents) || record.try(:amount_cents)
  end
end
