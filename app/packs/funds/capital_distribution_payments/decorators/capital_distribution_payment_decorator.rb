class CapitalDistributionPaymentDecorator < ApplicationDecorator
  def folio_id
    h.link_to object.folio_id, object.capital_commitment
  end

  def distribution_name
    h.link_to object.capital_distribution.title, object.capital_distribution
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
