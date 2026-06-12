module ValuationsHelper
  def valuations_chart(entity, owner_id: nil, owner_type: nil, valuations: nil)
    unless valuations
      valuations = entity.valuations.includes(:investment_instrument)
      valuations = valuations.where(owner_id: owner_id, owner_type: owner_type) if owner_id.present? && owner_type.present?
    end
    valuations = valuations.order(valuation_date: :asc)

    # Group valuations by investment_instrument name
    valuations_by_instrument = valuations.group_by { |v| v.investment_instrument&.name }

    # Transform data for chartkick
    data_series = valuations_by_instrument.map do |instrument_name, vals|
      {
        name: instrument_name,
        data: vals.map { |v| [v.valuation_date, v.per_share_value.cents / 100.0] }
      }
    end

    # Render line chart with multiple series
    line_chart data_series, id: "valuations-line-chart", curve: false, library: {
      plotOptions: { line: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } }, **chart_theme_color
    }, prefix: "#{entity.currency}:"
  end

  def valuation_json_fields_charts(_entity, valuations)
    return [] if valuations.blank?

    # Get all unique keys from json_fields
    keys = valuations.flat_map { |v| v.json_fields&.keys }.compact.uniq

    charts = []
    keys.each do |key|
      # Check if values for this key are numeric
      # We check a sample or all. Let's check all to be sure.
      numeric_values = valuations.filter_map { |v| v.json_fields[key] }
      next if numeric_values.empty?
      next unless numeric_values.all? { |v| v.is_a?(Numeric) || v.to_s.match?(/\A-?\d+\.?\d*\z/) }

      # Group by instrument
      data_series = valuations.group_by { |v| v.investment_instrument&.name || "Default" }.map do |instrument_name, vals|
        {
          name: instrument_name,
          data: vals.select { |v| v.json_fields[key].present? }.map { |v| [v.valuation_date, v.json_fields[key].to_f] }.sort_by { |d| d[0] }
        }
      end

      # Skip if no data points after selection
      next if data_series.all? { |s| s[:data].empty? }

      charts << {
        title: key.titleize,
        chart: line_chart(data_series, id: "valuation-#{key.parameterize}-chart", curve: false, library: {
                            plotOptions: { line: {
                              dataLabels: {
                                enabled: true,
                                format: "{point.y:,.2f}"
                              }
                            } }, **chart_theme_color
                          })
      }
    end
    charts
  end
end
