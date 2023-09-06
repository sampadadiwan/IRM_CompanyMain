class InvestorKycDecorator < ApplicationDecorator
  def expired
    h.render partial: "investor_kycs/expired", locals: { investor_kyc: object }, formats: [:html]
  end

  def full_name
    if object.full_name.blank?
      h.link_to "", h.investor_kyc_path(id: object.id)
    else
      h.link_to object.full_name, h.investor_kyc_path(id: object.id)
    end
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.investor_kyc_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_investor_kyc_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
