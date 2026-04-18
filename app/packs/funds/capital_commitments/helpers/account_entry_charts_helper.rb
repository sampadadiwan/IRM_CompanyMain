module AccountEntryChartsHelper
  def account_entries_chart(fund, entry_names: [], chart_type: 'column', aggregate_by: 'quarter', number_of_periods: 8, compact: false)
    return "No account entry names provided" if entry_names.blank?

    entries = fund.account_entries.where(name: entry_names).not_cumulative

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

    # Time-series aggregation (Quarter or Year)
    group_field = aggregate_by.to_s.downcase == 'year' ? "EXTRACT(YEAR FROM reporting_date)" : :period

    # Get the raw data: { [period, name] => sum }
    raw_data = entries.group(group_field, :name).sum(:amount_cents)

    # Get all unique periods in correct chronological order
    all_periods = if aggregate_by.to_s.downcase == 'year'
                    raw_data.keys.map(&:first).uniq.sort
                  else
                    raw_data.keys.map(&:first).uniq.sort_by { |p| q, y = p.split('-'); "#{y}#{q}" }
                  end

    # Apply number_of_periods limit
    all_periods = all_periods.last(number_of_periods) if number_of_periods

    # Pivot data into series format for Chartkick: [{ name: "Entry 1", data: { "Q1-2024" => 100 } }, ...]
    series_data = entry_names.map do |name|
      data_points = all_periods.each_with_object({}) do |period, hash|
        amount = raw_data[[period, name]] || 0
        hash[period] = amount / 100.0
      end
      { name: name, data: data_points }
    end

    # If it's a time series, bar should default to column
    chart_type = 'column' if chart_type == 'bar' && %w[quarter year].include?(aggregate_by.to_s.downcase)

    render_chart(chart_type, series_data, chart_options)
  end

  private

  def render_chart(type, data, options)
    case type.to_s.downcase
    when 'pie'
      pie_chart data, **options, donut: true
    when 'line'
      line_chart data, **options
    when 'column'
      column_chart data, **options
    else # bar
      bar_chart data, **options
    end
  end
end
