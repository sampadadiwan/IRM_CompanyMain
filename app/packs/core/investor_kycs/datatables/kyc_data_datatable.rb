class KycDataDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "KycData.id", searchable: false },
      full_name: { source: "InvestorKyc.full_name", searchable: false, orderable: true },
      created_at: { source: "KycData.created_at", orderable: true },
      source: { source: "KycData.source", searchable: true, orderable: true },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        full_name: record.investor_kyc.full_name,
        created_at: record.created_at.strftime("%d %B, %Y - %I:%M:%S %p %Z(%:::z)"),
        source: record.source.upcase,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "kyc_data_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def kyc_datas
    @kyc_datas ||= options[:kyc_datas]
  end

  def get_raw_records
    # insert query here
    kyc_datas
  end
end
