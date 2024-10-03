class CapitalCommitmentDecorator < ApplicationDecorator
  def full_name
    h.link_to capital_commitment.investor_kyc.full_name, h.investor_kyc_path(id: capital_commitment.investor_kyc) if capital_commitment.investor_kyc
  
  end

  def percentage
    "#{object.percentage.round(2)} %"
  end

  def custom_fields
    object.json_fields
  end

  def onboarding_completed
    h.display_boolean(object.onboarding_completed)
  end

  def folio_link
    h.link_to object.folio_id, object
  end

  def full_name_link
    name = object.investor_kyc&.full_name || ""
    h.link_to name, object.investor_kyc if object.investor_kyc
  end

  def pending_call_amount
    h.render partial: "/capital_commitments/pending_amount", locals: { capital_commitment: object }, formats: [:html]
  end

  def document_names(params)
    params[:show_docs].present? ? object.documents.collect(&:name).join(", ") : ""
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.capital_commitment_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_capital_commitment_path(object), class: "btn btn-outline-success") if h.policy(object).update?
    h.safe_join(links, '')
  end
end
