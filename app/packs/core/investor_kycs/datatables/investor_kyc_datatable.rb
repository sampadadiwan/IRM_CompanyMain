class InvestorKycDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "InvestorKyc.id" },
      full_name: { source: "InvestorKyc.full_name", orderable: true },
      investor_name: { source: "InvestorKyc.investor_name", orderable: true },
      pan: { source: "InvestorKyc.PAN", orderable: true },
      address: { source: "InvestorKyc.address" },
      bank_account_number: { source: "InvestorKyc.bank_account_number" },
      ifsc_code: { source: "InvestorKyc.ifsc_code" },
      pan_verified: { source: "InvestorKyc.pan_verified" },
      bank_verified: { source: "InvestorKyc.bank_verified" },
      verified: { source: "InvestorKyc.verified" },
      expired: { source: "InvestorKyc.expiry_date" },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        full_name: record.full_name,
        investor_name: record.decorate.investor_link,
        pan: record.PAN,
        address: record.address,
        bank_account_number: record.bank_account_number,
        ifsc_code: record.ifsc_code,
        pan_verified: record.decorate.display_boolean(record.pan_verified),
        bank_verified: record.decorate.display_boolean(record.bank_verified),
        verified: record.decorate.display_boolean(record.verified),
        expired: record.decorate.expired,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "investor_kyc_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def investor_kycs
    @investor_kycs ||= options[:investor_kycs]
  end

  def get_raw_records
    # insert query here
    investor_kycs
  end

  def search_for
    []
  end
end
