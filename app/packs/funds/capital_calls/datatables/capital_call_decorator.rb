class CapitalCallDecorator < ApplicationDecorator
  delegate :last_name, :bio

  def percentage_called
    "#{object.percentage_called.round(2)} %"
  end

  def name_link
    h.link_to object.name, object
  end

  def fund_link
    h.link_to object.fund.name, object.fund
  end

  def percentage_raised
    h.render partial: "/capital_calls/percentage_raised", locals: { capital_call: object }, formats: [:html]
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.capital_call_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to('Edit', h.edit_capital_call_path(object), class: "btn btn-outline-success ti ti-edit") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
