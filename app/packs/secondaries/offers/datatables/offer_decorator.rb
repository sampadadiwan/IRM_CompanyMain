class OfferDecorator < ApplicationDecorator
  def quantity
    h.custom_format_number(object.quantity)
  end

  def price
    h.custom_format_number(object.price)
  end

  def allocation_quantity
    h.custom_format_number(object.allocation_quantity)
  end

  def allocation_percentage
    "#{object.allocation_percentage.round(2)} %"
  end

  def percentage
    h.render partial: "/offers/percentage", locals: { offer: object }, formats: [:html]
  end

  def investor_link
    h.link_to object.investor.investor_name, h.investor_path(id: object.investor_id)
  end

  def bank_verification_enabled?
    entity.entity_setting.bank_verification && !secondary_sale.disable_bank_kyc
  end

  def pan_verification_enabled?
    entity.entity_setting.pan_verification && !secondary_sale.disable_pan_kyc
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to(h.t_common(:show), h.offer_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to("Complete Offer Details", h.edit_offer_path(offer), class: "btn btn-outline-warning ti ti-check") if object.approved && h.policy(object).edit?
    h.safe_join(links, '')
  end
end
