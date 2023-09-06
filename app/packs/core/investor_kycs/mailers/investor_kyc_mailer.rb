class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  def notify_kyc_updated
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_kyc, @user.email)
    cc = @investor_kyc.entity.entity_setting.cc
    if email.present?
      subj = "KYC updated for #{@investor_kyc.full_name}"
      mail(from: from_email(@investor_kyc.entity),
           cc:,
           to: email,
           subject: subj)
    end
  end

  def notify_kyc_verified
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_kyc, @user.email)
    cc = @investor_kyc.entity.entity_setting.cc

    if email.present?
      subj = "Confirmation of your KYC: #{@investor_kyc.entity.name}"
      mail(from: from_email(@investor_kyc.entity),
           cc:,
           to: email,
           subject: subj)
    end
  end

  def notify_kyc_required
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_kyc, @user.email)
    cc = @investor_kyc.entity.entity_setting.cc

    if email.present?
      subj = "Request to add KYC: #{@investor_kyc.entity.name}"
      mail(from: from_email(@investor_kyc.entity),
           to: email,
           cc:,
           subject: subj)
    end
  end

  def kyc_required_reminder
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_kyc, @user.email)
    cc = @investor_kyc.entity.entity_setting.cc

    if email.present?
      subj = "Reminder to update KYC: #{@investor_kyc.entity.name}"
      mail(from: from_email(@investor_kyc.entity),
           to: email,
           cc:,
           subject: subj)
    end
  end
end
