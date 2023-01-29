class CapitalCommitmentDatatable < AjaxDatatablesRails::ActiveRecord
  def view_columns
    @view_columns ||= {
      id: { source: "CapitalCommitment.id", searchable: false },
      folio_id: { source: "CapitalCommitment.folio_id", orderable: true },
      investor_name: { source: "CapitalCommitment.investor_name", orderable: true },
      fund_name: { source: "Fund.name", searchable: false, orderable: true },
      committed_amount: { source: "CapitalCommitment.committed_amount_cents", searchable: false },
      collected_amount: { source: "CapitalCommitment.collected_amount_cents", searchable: false },
      percentage: { source: "CapitalCommitment.percentage", searchable: false },
      onboarding_completed: { source: "CapitalCommitment.onboarding_completed", searchable: false },
      document_names: { source: "" },
      dt_actions: { source: "" }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        folio_id: record.folio_id,
        investor_name: record.decorate.investor_link,
        fund_name: record.decorate.fund_link,
        committed_amount: record.decorate.money_to_currency(record.committed_amount, params),
        collected_amount: record.decorate.money_to_currency(record.collected_amount, params),
        percentage: record.decorate.percentage,
        onboarding_completed: record.decorate.onboarding_completed,
        document_names: record.decorate.document_names(params),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "capital_commitment_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def capital_commitments
    @capital_commitments ||= options[:capital_commitments]
  end

  def get_raw_records
    # insert query here
    if params[:show_docs]
      # Dont load the docs unless we need them
      capital_commitments.includes(:documents)
    else
      capital_commitments
    end
  end
end
