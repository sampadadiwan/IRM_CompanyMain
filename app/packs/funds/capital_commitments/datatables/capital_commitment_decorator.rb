class CapitalCommitmentDecorator < ApplicationDecorator
  delegate :last_name, :bio

  def percentage
    "#{object.percentage.round(2)} %"
  end

  def onboarding_completed
    h.display_boolean(object.onboarding_completed)
  end

  def document_names(params)
    params[:show_docs].present? ? object.documents.collect(&:name).join(", ") : ""
  end

  # Just an example of a complex method you can add to you decorator
  # To render it in a datatable just add a column 'dt_actions' in
  # 'view_columns' and 'data' methods and call record.decorate.dt_actions
  def dt_actions
    links = []
    links << h.link_to('Show', h.capital_commitment_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_capital_commitment_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
