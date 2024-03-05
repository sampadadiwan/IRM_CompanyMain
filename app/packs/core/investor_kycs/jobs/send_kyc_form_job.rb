class SendKycFormJob < ApplicationJob
  def perform(investor_kyc_id, _user_id: nil, reminder: false)
    Chewy.strategy(:sidekiq) do
      investor_kyc = InvestorKyc.find(investor_kyc_id)
      investor_kyc.send_kyc_form(reminder:)
    end
  end
end
