class InvestorDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "Investor.id", searchable: false },
      investor_name: { source: "Investor.investor_name", orderable: true },
      category: { source: "Investor.category",  orderable: true },
      tag_list: { source: "Investor.tag_list",  orderable: true },
      city: { source: "Investor.city", orderable: true },
      access: { source: "", orderable: false, searchable: false },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        investor_name: record.investor_name,
        category: record.category,
        tag_list: record.tag_list,
        access: record.decorate.access,
        city: record.city,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "investor_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def investors
    @investors ||= options[:investors]
  end

  def get_raw_records
    # insert query here
    investors
  end
end
