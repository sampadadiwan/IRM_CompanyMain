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
                                   .where.not(submission_status: %w[completed verified])
                      end

      investor_kycs.each do |investor_kyc|
        # Skip any individually-specified KYC that is already completed or verified.
        next if investor_kyc.submission_completed? || investor_kyc.submission_verified?

        # Send to each investor user so the mailer generates a signed link for the right person.
        investor_kyc.investor.notification_users(with_tag: 'KYC').each do |inv_user|
          InvestorKycNotifier.with(
            record: investor_kyc,
            entity_id: investor_kyc.entity_id,
            email_method: :kyc_required_reminder,
            user_id: inv_user.id
          ).deliver_later(inv_user)
        end
      end
    end
  end
end
