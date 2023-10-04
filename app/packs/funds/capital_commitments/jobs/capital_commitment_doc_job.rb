class CapitalCommitmentDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(capital_commitment_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      capital_commitment = CapitalCommitment.find(capital_commitment_id)
      fund = capital_commitment.fund
      investor = capital_commitment.investor
      investor_kyc = capital_commitment.investor_kyc
      templates = capital_commitment.templates("Commitment Template")
      validate(fund, investor, investor_kyc, templates, user_id)

      if templates.present? && investor_kyc.present?
        Rails.logger.debug { "Generating documents for #{investor.investor_name}, for fund #{fund.name}" }

        templates.each do |fund_doc_template|
          existing_doc = capital_commitment.documents.where(name: fund_doc_template.name).first
          if existing_doc.present? && existing_doc.sent_for_esign
            msg = "Not generating #{fund_doc_template.name} for fund #{fund.name}, for user #{investor_kyc.full_name}, already sent for esign"
            Rails.logger.debug msg
            UserAlert.new(user_id:, level: :info, message: msg).broadcast
          else
            msg = "Generating #{fund_doc_template.name} for fund #{fund.name}, for #{investor_kyc.full_name}"
            Rails.logger.debug msg
            UserAlert.new(user_id:, level: :info, message: msg).broadcast
            # Delete any existing signed documents
            # Do not delete signed documents
            docs_to_destroy = capital_commitment.documents.where(name: fund_doc_template.name)
            # .where.not translates to != in SQL. NULL is treated differently from other values, so != queries never match columns that are set to NULL
            docs_to_destroy.where.not(owner_tag: %w[Signed signed]).or(docs_to_destroy.where(owner_tag: nil)).each(&:destroy)
            # Generate a new signed document
            CapitalCommitmentDocGenerator.new(capital_commitment, fund_doc_template, user_id)
          end
        end
      end
    end
  end

  def validate(fund, investor, investor_kyc, templates, user_id)
    if investor_kyc.blank? || !investor_kyc.verified
      msg = "Not generating documents for #{investor.investor_name}, for fund #{fund.name}, no verified KYC"
      UserAlert.new(user_id:, level: :danger, message: msg).broadcast
    end

    if templates.blank?
      msg = "Not generating documents for #{investor.investor_name}, for fund #{fund.name}, no templates found"
      Rails.logger.debug msg
      UserAlert.new(user_id:, level: :info, message: msg).broadcast
    end
  end
end
