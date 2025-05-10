class InvestorDecorator < ApplicationDecorator
  def tag_list
    h.raw object.tag_list&.split(",")&.collect { |tag| h.link_to(tag, h.search_investors_path(query: tag)) }&.join(", ") if object.tag_list
  end

  def investor_name
    h.link_to object.investor_name, h.investor_path(id: object.id)
  end

  def investor_access_count
    h.render partial: "/investors/access", locals: { investor: object }, formats: [:html]
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.investor_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_investor_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
