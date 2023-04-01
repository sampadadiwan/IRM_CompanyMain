class CapitalCommitmentDecorator < ApplicationDecorator
  delegate :last_name, :bio

  def percentage
    "#{object.percentage.round(2)} %"
  end

  def onboarding_completed
    h.display_boolean(object.onboarding_completed)
  end

  def folio_link
    h.link_to object.folio_id, object
  end

  def full_name_link
    h.link_to object.investor_kyc.full_name, object.investor_kyc if object.investor_kyc
  end

  def pending_call_amount
    h.render partial: "/capital_commitments/pending_amount", locals: { capital_commitment: object }, formats: [:html]
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
