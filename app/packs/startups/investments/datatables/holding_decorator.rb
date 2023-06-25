class HoldingDecorator < ApplicationDecorator
  def user_name
    object.user ? object.user.full_name : object.investor.investor_name
  end

  def status
    h.render partial: "/holdings/status", locals: { holding: object }, formats: [:html]
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.holding_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_holding_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
