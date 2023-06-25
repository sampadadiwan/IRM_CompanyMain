class CapitalRemittanceDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "CapitalRemittance.id" },
      investor_name: { source: "CapitalRemittance.investor_name" },
      folio_id: { source: "CapitalRemittance.folio_id" },
      call_amount: { source: "CapitalRemittance.call_amount_cents" },
      collected_amount: { source: "CapitalRemittance.collected_amount_cents" },
      due_amount: { source: "", orderable: false },
      status: { source: "CapitalRemittance.status" },
      verified: { source: "CapitalRemittance.verified" },
      payment_date: { source: "CapitalRemittance.payment_date" },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        payment_date: record.decorate.payment_date,
        folio_id: record.decorate.folio_id,
        investor_name: record.decorate.investor_link,
        call_amount: record.decorate.money_to_currency(record.call_amount, params),
        collected_amount: record.decorate.money_to_currency(record.collected_amount, params),
        due_amount: record.decorate.due_amount,
        verified: record.decorate.display_boolean(record.verified),
        status: record.status,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "capital_remittance_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def capital_remittances
    @capital_remittances ||= options[:capital_remittances]
  end

  def get_raw_records
    # insert query here
    capital_remittances
  end

  def search_for
    []
  end
end
