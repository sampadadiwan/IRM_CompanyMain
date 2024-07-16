module KeyBizMetricsHelper
  def kpi_biz_metrics_lines_by_date(kpi_biz_metrics, id: nil)
    dates = kpi_biz_metrics.pluck(:run_date).uniq.sort
    grouped_metrics = kpi_biz_metrics.group_by(&:name)

    data_map = []
    grouped_metrics.each do |name, metrics|
      data = []
      dates.each do |date|
        key_biz_metric = metrics.find { |k| k.run_date == date }
        data << [date.strftime("%m/%y"), key_biz_metric&.value]
      end

      label = name
      data_map << { name: label.to_s, data: }
    end

    line_chart data_map, id:, library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  def kpi_biz_metrics_cumulative_by_date(kpi_biz_metrics, id: nil)
    dates = kpi_biz_metrics.pluck(:run_date).uniq.sort
    grouped_metrics = kpi_biz_metrics.group_by(&:name)

    data_map = []
    grouped_metrics.each do |name, metrics|
      data = []
      cumulative_value = 0
      dates.each do |date|
        key_biz_metric = metrics.find { |k| k.run_date == date }
        cumulative_value += key_biz_metric.value if key_biz_metric&.value
        data << [date.strftime("%m/%y"), cumulative_value]
      end

      label = name
      data_map << { name: label.to_s, data: }
    end

    line_chart data_map, id:, library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end
end
