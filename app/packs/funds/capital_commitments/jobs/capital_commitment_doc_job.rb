class CapitalCommitmentDocJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(capital_commitment_id, user_id = nil, template_name: nil)
    error_msg = []
    msg = ""
    Chewy.strategy(:sidekiq) do
      capital_commitment = CapitalCommitment.find(capital_commitment_id)
      capital_commitment.fund
      investor_kyc = capital_commitment.investor_kyc
      templates = capital_commitment.templates("Commitment Template", template_name)

      valid = validate(capital_commitment, investor_kyc, templates, user_id, error_msg)

      if valid
        msg = "Generating documents for #{capital_commitment.investor_name}"
        send_notification(msg, user_id, :info)
        Rails.logger.debug { msg }

        templates.each do |fund_doc_template|
          process_template(fund_doc_template, capital_commitment, investor_kyc, user_id, error_msg)
        end

        msg = "Document generation completed for #{capital_commitment.investor_name}"
        send_notification(msg, user_id, :success)
      end

      send_notification("No templates found for #{capital_commitment.investor_name}", user_id, :danger) if templates.blank?
    end

    error_msg
  end

  def process_template(fund_doc_template, capital_commitment, investor_kyc, user_id, error_msg)
    existing_doc = capital_commitment.documents.where(name: fund_doc_template.name).first
    if existing_doc.present? && existing_doc.sent_for_esign
      msg = "Not generating #{fund_doc_template.name} for #{capital_commitment.investor_name}, already sent for esign"
      handle_error(msg, fund_doc_template, capital_commitment, investor_kyc, user_id, error_msg)
    else
      msg = "Generating #{fund_doc_template.name}, for #{investor_kyc.full_name}"
      Rails.logger.debug msg
      send_notification(msg, user_id, :info)

      destroy_existing(capital_commitment, fund_doc_template)

      # Generate a new signed document
      CapitalCommitmentDocGenerator.new(capital_commitment, fund_doc_template, user_id)
    end
  rescue Exception => e
    msg = "Error generating #{fund_doc_template.name}, for #{investor_kyc.full_name} #{e.message}"
    handle_error(msg, fund_doc_template, capital_commitment, investor_kyc, user_id, error_msg)
    raise e
  end

  def destroy_existing(capital_commitment, fund_doc_template)
    # Delete any existing signed documents
    # Do not delete signed documents
    docs_to_destroy = capital_commitment.documents.not_templates.where(name: fund_doc_template.name)
    # .where.not translates to != in SQL. NULL is treated differently from other values, so != queries never match columns that are set to NULL
    docs_to_destroy.where.not(owner_tag: %w[Signed signed]).or(docs_to_destroy.where(owner_tag: nil)).find_each(&:destroy)
  end

  def validate(capital_commitment, investor_kyc, templates, user_id, error_msg)
    if investor_kyc.blank? || !investor_kyc.verified
      msg = "Not generating documents for #{capital_commitment.investor_name}, no verified KYC"
      handle_error(msg, nil, capital_commitment, investor_kyc, user_id, error_msg)
      return false
    end

    if templates.blank?
      msg = "Not generating documents for #{capital_commitment.investor_name}, no templates found"
      handle_error(msg, nil, capital_commitment, investor_kyc, user_id, error_msg)
      return false
    end

    true
  end

  def handle_error(msg, fund_doc_template, capital_commitment, _investor_kyc, user_id, error_msg)
    send_notification(msg, user_id, :danger)
    error_msg << { msg:, template: fund_doc_template&.name, folio_id: capital_commitment.folio_id, investor_name: capital_commitment.to_s }
  end
end
