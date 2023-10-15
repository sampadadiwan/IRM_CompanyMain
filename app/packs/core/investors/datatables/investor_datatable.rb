class InvestorDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "Investor.id" },
      # entity_name: { source: "Entity.name" },
      investor_name: { source: "Investor.investor_name", orderable: true },
      pan: { source: "Investor.pan", orderable: true },
      category: { source: "Investor.category",  orderable: true },
      tag_list: { source: "Investor.tag_list",  orderable: true },
      city: { source: "Investor.city", orderable: true },
      access: { source: "", orderable: false },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        # entity_name: record.entity.name,
        investor_name: record.decorate.investor_link,
        pan: record.pan,
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

  def search_for
    []
  end
end
