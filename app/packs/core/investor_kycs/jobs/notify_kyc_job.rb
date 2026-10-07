class NotifyKycJob < ApplicationJob
  def perform(investor_kyc_id, email_method:, msg:)
    Chewy.strategy(:sidekiq) do
      InvestorKyc.find(investor_kyc_id).notify_kyc(msg:, email_method:)
    end
  end
end
