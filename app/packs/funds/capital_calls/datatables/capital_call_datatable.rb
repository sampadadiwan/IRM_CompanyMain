class CapitalCallDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "CapitalCall.id", searchable: false },
      name: { source: "CapitalCall.name", searchable: true, orderable: true },
      fund_name: { source: "Fund.name", searchable: true, orderable: true },
      call_amount: { source: "CapitalCall.call_amount_cents", searchable: false },
      due_date: { source: "CapitalCall.due_date", searchable: false, orderable: true },
      collected_amount: { source: "CapitalCall.collected_amount_cents", searchable: false },
      due_amount: { source: "", orderable: false, searchable: false },
      percentage_called: { source: "CapitalCall.percentage_called", searchable: false },
      approved: { source: "CapitalCall.approved", searchable: false },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        name: record.decorate.name_link,
        fund_name: record.decorate.fund_link,
        call_amount: record.decorate.money_to_currency(record.call_amount, params),
        collected_amount: record.decorate.percentage_raised,
        due_amount: record.decorate.money_to_currency(record.due_amount, params),
        percentage_called: record.decorate.percentage_called,
        approved: record.decorate.display_boolean(record.approved),
        due_date: record.decorate.display_date(record.due_date),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "capital_call_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def capital_calls
    @capital_calls ||= options[:capital_calls]
  end

  def get_raw_records
    # insert query here
    capital_calls.joins(:fund)
  end
end
