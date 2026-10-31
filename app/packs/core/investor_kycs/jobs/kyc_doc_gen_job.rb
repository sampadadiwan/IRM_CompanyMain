class KycDocGenJob < DocGenJob
  # Returns all the templates from which documents will be generated.
  # M9 — the picked ids are resolved only among template documents of the KYC's own firm (the KYC
  # Templates folder, or the fund / commitment statement templates of that firm). Another firm's
  # document id finds nothing, so the run stops with "No templates found" and never renders that
  # template or deletes this KYC's same-named generated documents.
  # Tests M9-X2, M9-H3 — features/security/security_review_2026_10_funds.feature
  def templates(model = nil)
    # The KYC being generated for, or (during the input check) the first KYC of the run
    firm_id = model ? model.entity_id : models&.first&.entity_id
    Document.templates.where(id: @document_template_ids, entity_id: firm_id)
  end

  # Returns all the KYCs for which documents will be generated
  def models
    # M9 — an explicit id list (even an empty one, when the caller's scoped search matched nothing) is
    # authoritative; only a run started with no ids at all falls back to the whole entity (M9-E1)
    if @investor_kyc_id.nil?
      # No ids at all: every KYC of the entity the caller named
      InvestorKyc.where("entity_id=?", @entity_id) if @entity_id.present?
    else
      InvestorKyc.where(id: @investor_kyc_id)
    end
  end

  # Validates the KYC before generating the document
  def validate(investor_kyc)
    [investor_kyc.verified, "#{investor_kyc.full_name} is not verified"]
  end

  def generator
    KycDocGenerator
  end

  # Validates the inputs before generating the document
  def valid_inputs
    return false unless super

    if @start_date > @end_date
      send_notification("Invalid Dates", @user_id, "danger")
      false
    end
    if @document_template_ids.blank?
      send_notification("Invalid Document Template", @user_id, "danger")
      false
    end
    true
  end

  def cleanup_previous_docs(model, template)
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def generate_doc_name(model, template, start_date, end_date)
    is_soa_doc = template.is_soa_template?

    if is_soa_doc && start_date && end_date
      "#{template.name} #{start_date} to #{end_date} - #{model}"
    else
      "#{template.name} - #{model}"
    end
  end

  def perform(investor_kyc_id, document_template_ids, start_date, end_date,
              user_id, entity_id: nil, options: {})
    @document_template_ids = document_template_ids
    @investor_kyc_id = investor_kyc_id
    @entity_id = entity_id
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id, options:) if valid_inputs
    end
  end
end
