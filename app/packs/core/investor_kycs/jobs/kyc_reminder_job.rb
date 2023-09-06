class KycReminderJob < ApplicationJob
  queue_as :default

  after_perform do |job|
    UserAlert.new(user_id: job.arguments.first, message: "KYC Reminders Sent to All", level: "success").broadcast if job.arguments.first.present?
  end

  def perform(user_id, investor_kyc_id = nil)
    Chewy.strategy(:sidekiq) do
      @user = User.find(user_id)
      investor_kycs = if investor_kyc_id.present?
                        [InvestorKyc.find(investor_kyc_id)]
                      else
                        InvestorKyc.where(entity_id: @user.entity_id, verified: false)
                      end

      investor_kycs.each do |investor_kyc|
        InvestorKycNotification.with(entity_id: investor_kyc.entity_id, investor_kyc:, user_id: @user.id).notify_kyc_required_inv_kyc.deliver_later(@user)
      end
    end
  end
end
