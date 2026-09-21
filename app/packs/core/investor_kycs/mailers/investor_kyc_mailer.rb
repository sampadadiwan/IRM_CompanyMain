class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@investor_kyc)&.full_name },
    "fund_name" => ->(m) { m.instance_variable_get(:@investor_kyc)&.entity&.name },
    "committed_amount" => ->(m) { m.instance_variable_get(:@investor_kyc)&.committed_amount&.format }
  ).freeze

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

  private

  # Same override, for the same reason, as CapitalCommitmentMailer / FundInvestorKycMailer:
  # the ApplicationMailer default (@notification&.model) is correct for real sends
  # (InvestorKycNotifier passes record: investor_kyc, so @notification.model IS @investor_kyc),
  # but WithEmailPreview builds no Noticed::Notification, so @notification is nil there.
  # Without this, the "Preview KYC Required" / "Preview KYC Required Reminder" links rendered
  # zero attachment_names-matched documents even when the real email would attach them.
  #
  # private: keeps this resolver out of CustomNotification#email_methods, which reads
  # instance_methods(false) on each mailer to populate the "For Notification" dropdown.
  def custom_notification_documents_owner
    @investor_kyc
  end
end
