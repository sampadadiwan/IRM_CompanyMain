class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  def notify_kyc_updated
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    if @to.present?
      subj = "KYC updated for #{@investor_kyc.full_name}"
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

    if @to.present?
      subj = "Request to add KYC: #{@investor_kyc.entity.name}"
      send_mail(subject: subj)
    end
  end

  def kyc_required_reminder
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])

    if @to.present?
      subj = "Reminder to update KYC: #{@investor_kyc.entity.name}"
      send_mail(subject: subj)
    end
  end
end
