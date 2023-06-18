module KpisHelper
  def kpi_lines_by_date(kpi_reports, kpi_type = nil)
    kpis = Kpi.joins(:kpi_report).where(kpi_report_id: kpi_reports.pluck(:id).uniq).order("kpi_reports.as_of asc").group_by(&:name)

    kpis = kpis.filter { |k, _v| KpiReport.custom_fields_map[k] == kpi_type } if kpi_type

    chart_data = kpis.map { |name, arr| [name:, data: arr.map { |kpi| [kpi.kpi_report.as_of.strftime("%m/%y"), kpi.value] }] }.flatten

    column_chart chart_data
  end
end
