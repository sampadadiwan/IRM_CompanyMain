class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  before_action :set_kyc
  def set_kyc
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @investor_kyc.entity.custom_notification(email_method, custom_notification_id: params[:custom_notification_id], for_type: "InvestorKyc")

    @message = params[:msg]

    # Generate a 30-day magic link for emails that go directly to the investor.
    if %i[notify_kyc_required kyc_required_reminder notify_updates_requested].include?(email_method&.to_sym)
      investor_user = User.find_by(id: params[:user_id])
      if investor_user
        @signed_id    = InvestorKyc.signed_id_for_user(@investor_kyc, investor_user, expires_in: 30.days)
        @link_expiry  = 30.days.from_now
      end
    end
  end

  def notify_kyc_updated
    subject = "KYC updated for #{@investor_kyc.full_name}"
    # Ensure no one gets cc'ed on this cause its sending too many dup emails to the cc folks
    @cc = nil
    send_mail(subject:)
  end

  def notify_kyc_submitted
    subject = "KYC submitted by #{@investor_kyc.full_name}"
    @cc = nil
    send_mail(subject:)
  end

  def notify_updates_requested
    subject = "Action Required: Please update your KYC details"
    send_mail(subject:)
  end

  def notify_kyc_required
    subject = "Request to add KYC: #{@investor_kyc.entity.name}"
    send_mail(subject:)
  end

  def kyc_required_reminder
    subject = "Reminder to update KYC: #{@investor_kyc.entity.name}"
    send_mail(subject:)
  end
end
