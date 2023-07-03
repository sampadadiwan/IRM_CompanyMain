class InvestorKycDecorator < ApplicationDecorator
  def expired
    h.render partial: "investor_kycs/expired", locals: { investor_kyc: object }, formats: [:html]
  end

  def committed_amount
    if object.properties["committed_amount"].present?
      h.money_to_currency(Money.new(object.properties["committed_amount"].to_f * 100, object.entity.currency), {})
    else
      h.money_to_currency(object.committed_amount, {})
    end
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.investor_kyc_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_investor_kyc_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
