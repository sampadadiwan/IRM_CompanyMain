class FundReportDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "FundReport.id", searchable: false },
      start_date: { source: "FundReport.start_date", orderable: true },
      end_date: { source: "FundReport.end_date", orderable: true },
      name_of_scheme: { source: "FundReport.name_of_scheme", orderable: true },
      name: { source: "FundReport.name", orderable: true },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        end_date: record.decorate.display_date(record.end_date),
        start_date: record.decorate.display_date(record.start_date),
        name_of_scheme: record.decorate.name_of_scheme,
        name: record.decorate.name,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "fund_report_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def fund_reports
    @fund_reports ||= options[:fund_reports]
  end

  def get_raw_records
    fund_reports
  end
end
