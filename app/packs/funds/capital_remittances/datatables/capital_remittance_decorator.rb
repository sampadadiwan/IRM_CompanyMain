class CapitalRemittanceDecorator < ApplicationDecorator
  def due_amount
    h.render partial: "/capital_remittances/due_amount", locals: { capital_remittance: object }, formats: [:html]
  end

  def folio_id
    h.link_to object.folio_id, object.capital_commitment
  end

  def collected_amount
    h.money_to_currency object.collected_amount
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.capital_remittance_path(object), class: "btn btn-outline-primary")
    # links << h.link_to('Edit', h.edit_capital_remittance_path(object), class: "btn btn-outline-success") if h.policy(object).update?

    if h.policy(object).verify?
      label = object.verified ? "Unverify" : "Verify"
      msg = object.verified ? "Mark as Unverified?" : "Mark as Verified?"
      links << h.button_to(label, h.verify_capital_remittance_path(object), method: :patch,
                                                                            class: "btn btn-outline-success", form_class: "deleteButton",
                                                                            data: { action: "click->confirm#popup", msg:, turbo: false, method: :patch })

    end
    h.safe_join(links, '')
  end
end
