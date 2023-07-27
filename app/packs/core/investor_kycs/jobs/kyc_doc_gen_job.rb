class KycDocGenJob < ApplicationJob
  queue_as :serial

  def perform(investor_kyc_id, document_template_ids, start_date, end_date, user_id = nil)
    Chewy.strategy(:sidekiq) do
      investor_kyc = InvestorKyc.find(investor_kyc_id)

      Document.where(id: document_template_ids).each do |document_template|
        KycDocGenerator.new(investor_kyc, document_template, start_date, end_date, user_id)
      end
    end
  end
end
