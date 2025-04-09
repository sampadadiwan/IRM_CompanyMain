module ValuationsHelper
  def valuations_chart(entity, owner_id: nil, owner_type: nil)
    valuations = entity.valuations.includes(:investment_instrument)
    valuations = valuations.where(owner_id: owner_id, owner_type: owner_type) if owner_id.present? && owner_type.present?
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
    line_chart data_series, curve: false, library: {
      plotOptions: { line: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } }
    }, prefix: "#{entity.currency}:"
  end
end
