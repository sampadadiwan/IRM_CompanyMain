class FundRatioDecorator < ApplicationDecorator
  def owner_name
    h.link_to object.owner if object.owner
  end

  def fund_name
    h.link_to object.fund.name, h.fund_path(object.fund)
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.fund_ratio_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_fund_ratio_path(object), class: "btn btn-outline-success") if object.import_upload_id.present?
    h.safe_join(links, '')
  end
end
