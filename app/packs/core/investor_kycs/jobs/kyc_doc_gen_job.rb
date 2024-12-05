class KycDocGenJob < DocGenJob
  # Returns all the templates from which documents will be generated
  def templates(_model = nil)
    Document.where(id: @document_template_ids)
  end

  # Returns all the KYCs for which documents will be generated
  def models
    if @investor_kyc_id.present?
      InvestorKyc.where(id: @investor_kyc_id)
    elsif @entity_id.present?
      InvestorKyc.where("entity_id=?", @entity_id)
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
    is_soa_doc = template.tag_list.downcase =~ /\b#{Regexp.escape('soa')}\b/

    if is_soa_doc && start_date && end_date
      "#{template.name} #{start_date} to #{end_date} - #{model}"
    else
      "#{template.name} - #{model}"
    end
  end

  def perform(investor_kyc_id, document_template_ids, start_date, end_date,
              user_id, entity_id: nil)

    @document_template_ids = document_template_ids
    @investor_kyc_id = investor_kyc_id
    @entity_id = entity_id
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end
  end
end
