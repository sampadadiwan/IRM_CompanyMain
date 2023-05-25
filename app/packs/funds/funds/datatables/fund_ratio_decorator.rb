class FundRatioDecorator < ApplicationDecorator
  def owner_name
    h.link_to object.owner if object.owner
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.fund_ratio_path(object), class: "btn btn-outline-primary")
    h.safe_join(links, '')
  end
end
