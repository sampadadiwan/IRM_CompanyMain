class CapitalDistributionPaymentDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "CapitalDistributionPayment.id", searchable: false },
      distribution_name: { source: "CapitalDistribution.title", searchable: false },
      folio_id: { source: "CapitalDistributionPayment.folio_id", searchable: true },
      investor_name: { source: "CapitalDistributionPayment.investor_name", searchable: true },
      income: { source: "CapitalDistributionPayment.income_cents", searchable: false },
      net_payable: { source: "CapitalDistributionPayment.net_payable_cents", searchable: false },
      gross_payable: { source: "CapitalDistributionPayment.gross_payable_cents", searchable: false },
      payment_date: { source: "CapitalDistributionPayment.payment_date", searchable: true },
      completed: { source: "CapitalDistributionPayment.completed", searchable: false },
      dt_actions: { source: "", orderable: false, searchable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        distribution_name: record.capital_distribution.title,
        folio_id: record.decorate.folio_id,
        investor_name: record.decorate.investor_link,
        income: record.decorate.income,
        net_payable: record.decorate.money_to_currency(record.net_payable, params),
        gross_payable: record.decorate.money_to_currency(record.gross_payable, params),
        completed: record.decorate.display_boolean(record.completed),
        payment_date: record.decorate.display_date(record.payment_date),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "capital_distribution_payment_#{record.id}" # This will automagically set the id attribute on the corresponding <tr> in the datatable
      }
    end
  end

  def capital_distribution_payments
    @capital_distribution_payments ||= options[:capital_distribution_payments]
  end

  def get_raw_records
    # insert query here
    capital_distribution_payments
  end

  def search_for
    []
  end
end
