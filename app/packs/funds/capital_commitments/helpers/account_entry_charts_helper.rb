module AccountEntryChartsHelper
  def account_entries_chart(fund, entry_names: [], chart_type: 'column', aggregate_by: 'quarter', number_of_periods: 8, compact: false, use_entries: 'folio_only')
    return "No account entry names provided" if entry_names.blank?

    entries = fund.account_entries.where(name: entry_names).not_cumulative

    entries = if use_entries.to_s == 'fund_only'
                entries.where(capital_commitment_id: nil)
              else
                entries.where.not(capital_commitment_id: nil)
              end

    chart_id = "account_entries_chart_#{fund.id}_#{SecureRandom.hex(4)}"
    # title = "Account Entries: #{entry_names.join(', ')}"
    title = ""
    chart_options = {
      title: title,
      id: chart_id,
      library: {
        **chart_theme_color
      },
      prefix: "#{fund.currency}:"
    }

    if aggregate_by.to_s.downcase == 'sum'
      data = entries.group(:name).sum(:amount_cents).transform_values { |v| v / 100.0 }
      return render_chart(chart_type, data, chart_options)
    end

    # Time-series aggregation (Month, Quarter or Year)
    group_field = case aggregate_by.to_s.downcase
                  when 'year'
                    "DATE_FORMAT(reporting_date, '%Y-12-31')"
                  when 'month'
                    "LAST_DAY(reporting_date)"
                  else # quarter
                    "LAST_DAY(DATE_ADD(DATE_FORMAT(reporting_date, '%Y-01-01'), INTERVAL (QUARTER(reporting_date) * 3 - 1) MONTH))"
                  end

    # Get the raw data: { [period, name] => sum }
    raw_data = entries.group(Arel.sql(group_field), :name).sum(:amount_cents)

    # Get all unique periods in correct chronological order
    all_periods = raw_data.keys.map(&:first).uniq.sort

    # Apply number_of_periods limit
    all_periods = all_periods.last(number_of_periods) if number_of_periods

    # Pivot data into series format for Chartkick: [{ name: "Entry 1", data: { "Q1-2024" => 100 } }, ...]
    series_data = entry_names.map do |name|
      data_points = all_periods.each_with_object({}) do |period, hash|
        date = if period.is_a?(Time) || period.is_a?(Date)
                 period
               elsif /^\d{4}-\d{2}-\d{2}$/.match?(period.to_s)
                 Date.parse(period.to_s)
               end

        label = if date
                  if aggregate_by.to_s.downcase == 'year'
                    date.strftime("%Y")
                  else
                    date.strftime("%m/%y")
                  end
                else
                  period.to_s
                end

        amount = raw_data[[period, name]] || 0
        hash[label] = amount / 100.0
      end
      { name: name, data: data_points }
    end

    # If it's a time series, bar should default to column
    chart_type = 'column' if chart_type == 'bar' && %w[month quarter year].include?(aggregate_by.to_s.downcase)

    render_chart(chart_type, series_data, chart_options)
  end

  private

  def render_chart(type, data, options)
    case type.to_s.downcase
    when 'pie'
      pie_chart data, **options, donut: true
    when 'line'
      line_chart data, **options
    when 'spline'
      line_chart data, **options, curve: true
    when 'area'
      area_chart data, **options
    when 'column'
      column_chart data, **options
    else # bar
      bar_chart data, **options
    end
  end
end
