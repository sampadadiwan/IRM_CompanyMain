class AccountEntryDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "AccountEntry.id", searchable: false },
      fund_name: { source: "Fund.name", searchable: true },
      investor_name: { source: "CapitalCommitment.investor_name", searchable: true },
      folio_id: { source: "AccountEntry.folio_id", orderable: true },
      unit_type: { source: "CapitalCommitment.unit_type", orderable: true },
      reporting_date: { source: "AccountEntry.reporting_date", orderable: true },
      period: { source: "AccountEntry.period", orderable: true },
      amount: { source: "AccountEntry.amount_cents", searchable: false },
      entry_type: { source: "AccountEntry.entry_type" },
      name: { source: "AccountEntry.name" },
      parent_name: { source: "AccountEntry.parent_name" },
      commitment_name: { source: "AccountEntry.commitment_name" },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        fund_name: record.fund.name,
        investor_name: record.capital_commitment&.investor_name,
        folio_id: record.decorate.folio_id,
        unit_type: record.capital_commitment&.unit_type,
        reporting_date: record.decorate.display_date(record.reporting_date),
        period: record.period,
        amount: record.decorate.amount,
        entry_type: record.decorate.entry_type,
        name: record.name,
        parent_name: record.decorate.parent_name,
        commitment_name: record.commitment_name,
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
