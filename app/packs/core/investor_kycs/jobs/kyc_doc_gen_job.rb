class KycDocGenJob < ApplicationJob
  queue_as :serial

  def perform(investor_kyc_id, document_template_ids, start_date, end_date,
              user_id: nil, entity_id: nil)

    Chewy.strategy(:sidekiq) do
      investor_kycs = [InvestorKyc.find(investor_kyc_id)] if investor_kyc_id.present?
      # # If we have a fund then lets get the kycs for that fund
      # investor_kycs ||= InvestorKyc.joins(:capital_commitments).where("capital_commitments.fund_id=?", fund_id) if fund_id.present?
      # If we have an entity then lets get the kycs for that entity
      investor_kycs ||= InvestorKyc.where("entity_id=?", entity_id) if entity_id.present?

      # Loop through each investor kyc and generate the documents
      investor_kycs.each do |investor_kyc|
        Document.where(id: document_template_ids).each do |document_template|
          KycDocGenerator.new(investor_kyc, document_template, start_date, end_date, user_id)
        end
      end
    end
  end
end
