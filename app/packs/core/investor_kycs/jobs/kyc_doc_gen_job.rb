class KycDocGenJob < ApplicationJob
  queue_as :serial

  def perform(investor_kyc_id, document_template_ids, start_date, end_date,
              user_id: nil, entity_id: nil)

    error_msg = []

    Chewy.strategy(:sidekiq) do
      investor_kycs = InvestorKyc.where(id: investor_kyc_id) if investor_kyc_id.present?
      # # If we have a fund then lets get the kycs for that fund
      # investor_kycs ||= InvestorKyc.joins(:capital_commitments).where("capital_commitments.fund_id=?", fund_id) if fund_id.present?
      # If we have an entity then lets get the kycs for that entity
      investor_kycs ||= InvestorKyc.where("entity_id=?", entity_id) if entity_id.present?

      # Loop through each investor kyc and generate the documents
      investor_kycs.each do |investor_kyc|
        # send_notification("Generating KYC documents for #{investor_kyc.full_name}", user_id)
        Document.where(id: document_template_ids).find_each do |document_template|
          send_notification("Generating #{document_template.name} for #{investor_kyc.full_name}", user_id)
          KycDocGenerator.new(investor_kyc, document_template, start_date, end_date, user_id)
        rescue Exception => e
          msg = "Error generating #{document_template.name} for #{investor_kyc.full_name} #{e.message}"
          send_notification(msg, user_id, "danger")
          # raise e
          error_msg << { msg:, template: document_template&.name, folio_id: investor_kyc.capital_commitment.folio_id, investor_name: investor_kyc.full_name }
        end
      end
    end

    if error_msg.present?
      send_notification("Documentation generation completed with errors. Errors will be sent via email", user_id, :danger)
      EntityMailer.with(entity_id: investor_kycs.last.entity_id, user_id:, error_msg:).doc_gen_errors.deliver_now
    end
    send_notification("Invalid Dates", user_id, "danger") if start_date > end_date
    send_notification("Invalid Document Template", user_id, "danger") if document_template_ids.blank?
  end
end
