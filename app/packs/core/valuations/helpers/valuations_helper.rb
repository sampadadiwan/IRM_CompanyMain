module ValuationsHelper
  def valuations_chart(entity)
    valuations = entity.valuations
                       .order(valuation_date: :asc)
                       .map { |v| [v.valuation_date, v.per_share_value.cents / 100] }

    line_chart valuations, curve: false, library: {
      plotOptions: { line: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } },
      **chart_theme_color
    }, prefix: "#{entity.currency}:"
  end
end
