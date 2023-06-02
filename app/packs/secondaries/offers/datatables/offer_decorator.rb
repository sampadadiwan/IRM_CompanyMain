class OfferDecorator < ApplicationDecorator
  def allocation_percentage
    "#{object.allocation_percentage.round(2)} %"
  end

  def percentage
    h.render partial: "/offers/percentage", locals: { offer: object }, formats: [:html]
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.offer_path(object), class: "btn btn-outline-primary")
    links << h.link_to("Complete Offer Details" , h.edit_offer_path(offer), class: "btn btn-outline-warning") if object.approved
    h.safe_join(links, '')
  end
end
