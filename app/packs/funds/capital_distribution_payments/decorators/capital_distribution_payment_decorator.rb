class CapitalDistributionPaymentDecorator < ApplicationDecorator
  def investing_entity_name
    if object.investor_kyc
      h.link_to(object.investor_kyc.full_name, h.investor_kyc_path(id: object.investor_kyc))
    else
      h.link_to(object.investor_name, object.investor)
    end
  end

  def folio_id
    h.link_to object.folio_id, object.capital_commitment
  end

  def distribution_name
    if h.current_user.entity_id == object.entity_id
      h.link_to object.capital_distribution.title, object.capital_distribution
    else
      object.capital_distribution.title
    end
  end

  def income
    h.money_to_currency object.income
  end

  def completed
    display_boolean(object.completed)
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.capital_distribution_payment_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_capital_distribution_payment_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
