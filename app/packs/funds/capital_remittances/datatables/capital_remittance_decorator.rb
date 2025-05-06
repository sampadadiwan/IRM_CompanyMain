class CapitalRemittanceDecorator < ApplicationDecorator
  # def due_amount
  #   h.render partial: "/capital_remittances/due_amount", locals: { capital_remittance: object }, formats: [:html]
  # end

  def folio_id
    h.link_to object.folio_id, object.capital_commitment
  end

  def capital_call_link
    h.link_to object.capital_call.name, object.capital_call
  end

  # def collected_amount
  #   h.money_to_currency object.collected_amount
  # end

  def investor_name
    h.link_to object.investor_name, object.investor
  end

  def verified
    h.display_boolean object.verified
  end

  def payment_date
    h.l object.payment_date if object.payment_date
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    h.render partial: "/capital_remittances/dt_actions", locals: { capital_remittance: object }, formats: [:html]
  end
end
