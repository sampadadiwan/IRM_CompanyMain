module KpisHelper
  def kpi_lines_by_date(kpi_reports, kpi_type = nil)
    kpis = Kpi.joins(:kpi_report).where(kpi_report_id: kpi_reports.pluck(:id).uniq).order("kpi_reports.as_of asc").group_by(&:name)

    kpis = kpis.filter { |k, _v| KpiReport.custom_fields_map[k] == kpi_type } if kpi_type

    chart_data = kpis.map { |name, arr| [name:, data: arr.map { |kpi| [kpi.kpi_report.as_of.strftime("%m/%y"), kpi.value] }] }.flatten

    column_chart chart_data
  end

  def multiple_entity_kpi_lines_by_date(kpis, id: nil, chart_title: nil)
    dates = KpiReport.where(id: kpis.pluck(:kpi_report_id)).order(as_of: :asc).pluck(:as_of).uniq
    grouped_kpis = kpis.group_by(&:entity)

    data_map = []
    grouped_kpis.each do |entity, entity_kpis|
      entity_kpis.group_by(&:name).each do |kpi_name, kpis_by_name|
        data = []
        dates.each do |date|
          kpi = kpis_by_name.find { |k| k.kpi_report.as_of == date }
          data << [date.strftime("%m/%y"), kpi&.value]
        end
        data_map << { name: "#{entity.name} - #{kpi_name}", data: }
      end
    end

    chart_name = chart_title ? "#{chart_title.delete(' ')}.jpg" : "chart.jpg"
    line_chart(data_map, id:, download: { filename: chart_name },
                         library: {
                           exporting: {
                             fallbackToExportServer: false
                           }
                         })
  end
end
