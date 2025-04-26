class KpiReportDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "KpiReport.id", searchable: false },
      period: { source: "KpiReport.period", searchable: true },
      user: { source: "User.first_name", orderable: true, searchable: true },
      entity: { source: "Entity.name", orderable: true, searchable: false },
      notes: { source: "Investor.notes", orderable: false, searchable: false },
      as_of: { source: "KpiReport.as_of", orderable: true },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        as_of: record.decorate.display_date(record.as_of),
        period: record.period,
        notes: record.notes,
        user: record.user.full_name,
        entity: record.decorate.entity_name,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "kpi_report_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def kpi_reports
    @kpi_reports ||= options[:kpi_reports]
  end

  def get_raw_records
    kpi_reports
  end
end
