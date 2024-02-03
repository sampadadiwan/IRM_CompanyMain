class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  def notify_kyc_updated
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @message = params[:message]
    if @to.present?
      subj = @message.presence || "KYC updated for #{@investor_kyc.full_name}"
      send_mail(subject: subj)
    end
  end

  def notify_kyc_verified
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])

    if @to.present?
      subj = "Confirmation of your KYC: #{@investor_kyc.entity.name}"
      send_mail(subject: subj)
    end
  end

  def notify_kyc_required
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @custom_notification = @investor_kyc.entity.custom_notification("InvestorKyc")
    subject = @custom_notification ? @custom_notification.subject : "Request to add KYC: #{@investor_kyc.entity.name}"

    send_mail(subject:) if @to.present?
  end

  def kyc_required_reminder
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @custom_notification = @investor_kyc.entity.custom_notification("InvestorKyc")
    subject = @custom_notification ? @custom_notification.subject : "Reminder to update KYC: #{@investor_kyc.entity.name}"

    send_mail(subject:) if @to.present?
  end
end
