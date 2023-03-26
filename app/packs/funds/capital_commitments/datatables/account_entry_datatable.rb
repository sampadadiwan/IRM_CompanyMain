class AccountEntryDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "AccountEntry.id", searchable: false },
      folio_id: { source: "AccountEntry.folio_id", orderable: true },
      reporting_date: { source: "AccountEntry.reporting_date", orderable: true },
      period: { source: "AccountEntry.period", orderable: true },
      amount: { source: "AccountEntry.amount_cents", searchable: false },
      entry_type: { source: "AccountEntry.entry_type" },
      name: { source: "AccountEntry.name" },
      commitment_type: { source: "AccountEntry.commitment_type" },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        folio_id: record.decorate.folio_id,
        reporting_date: record.decorate.display_date(record.reporting_date),
        period: record.period,
        amount: record.decorate.amount,
        entry_type: record.decorate.entry_type,
        name: record.name,
        commitment_type: record.commitment_type,
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "account_entry_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def account_entries
    @account_entries ||= options[:account_entries]
  end

  def get_raw_records
    account_entries
  end
end
