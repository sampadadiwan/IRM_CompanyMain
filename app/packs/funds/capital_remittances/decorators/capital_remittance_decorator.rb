class CapitalRemittanceDecorator < ApplicationDecorator
  # def due_amount
  #   h.render partial: "/capital_remittances/due_amount", locals: { capital_remittance: object }, formats: [:html]
  # end

  def folio_id
    h.link_to object.folio_id, object.capital_commitment
  end

  def capital_call_name
    if h.current_user.entity_id == object.entity_id
      h.link_to object.capital_call.name, object.capital_call
    else
      object.capital_call.name
    end
  end

  # def collected_amount
  #   h.money_to_currency object.collected_amount
  # end

  def investing_entity_name
    if object.investor_kyc
      h.link_to(object.investor_kyc.full_name, h.investor_kyc_path(id: object.investor_kyc))
    else
      h.link_to(object.investor_name, object.investor)
    end
  end

  def verified
    h.display_boolean object.verified
  end

  # Status badge colours for the LP grid - the same solid bg-* badges as the Completed column
  # (DisplayBooleanComponent); an unknown status falls back to a neutral badge
  LP_STATUS_BADGES = { "Paid" => "bg-success", "Overpaid" => "bg-info", "Pending" => "bg-warning", "Overdue" => "bg-danger" }.freeze

  # LP grid Status (INVESTOR_STANDARD_COLUMNS => lp_status): the status badge, plus a second badge when a
  # payment is recorded but not yet verified (model #lp_status has the same wording as plain text)
  def lp_status
    badges = [h.content_tag(:span, object.status, class: "badge #{LP_STATUS_BADGES.fetch(object.status, 'bg-secondary')}")]
    if !object.verified && object.collected_amount_cents.to_d.nonzero?
      badges << h.content_tag(:span, class: "badge bg-info ms-1", title: "Recorded by the fund, awaiting verification") do
        h.safe_join([h.content_tag(:i, nil, class: "ti ti-clock"), " Payment under verification"])
      end
    end
    h.safe_join(badges)
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
