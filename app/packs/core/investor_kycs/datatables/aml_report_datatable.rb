class AmlReportDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "AmlReport.id" },
      name: { source: "AmlReport.name", orderable: true },
      match_status: { source: "AmlReport.match_status", orderable: true },
      approved: { source: "AmlReport.approved", orderable: true },
      types: { source: "AmlReport.types", orderable: false },
      associates: { source: "", orderable: false },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        name: record.name,
        match_status: record.match_status,
        approved: record.decorate.aml_approved,
        types: record.types,
        associates: record.decorate.associates,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "aml_report_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def aml_reports
    @aml_reports ||= options[:aml_reports]
  end

  def get_raw_records
    # insert query here
    aml_reports
  end

  def search_for
    []
  end
end
