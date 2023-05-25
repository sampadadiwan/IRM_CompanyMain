class FundRatioDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "FundRatio.id", searchable: false },
      owner_name: { source: "", searchable: false, orderable: false },
      name: { source: "FundRatio.name", searchable: true, orderable: true },
      display_value: { source: "FundRatio.display_value", searchable: false, orderable: false },
      created_at: { source: "FundRatio.created_at", orderable: true },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        owner_name: record.decorate.owner_name,
        name: record.name,
        display_value: record.display_value,
        created_at: record.created_at.strftime("%d %B, %Y - %I:%M:%S %p %Z(%:::z)"),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "fund_ratio_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def fund_ratios
    @fund_ratios ||= options[:fund_ratios]
  end

  def get_raw_records
    # insert query here
    fund_ratios
  end
end
