module KpisHelper
  def kpi_lines_by_date(kpi_reports)
    kpis = Kpi.joins(:kpi_report).where(kpi_report_id: kpi_reports.pluck(:id).uniq).order("kpi_reports.as_of asc").group_by(&:name)

    chart_data = kpis.map { |name, arr| [name:, data: arr.map { |kpi| [kpi.kpi_report.as_of, kpi.value] }] }.flatten

    line_chart chart_data
  end
end
