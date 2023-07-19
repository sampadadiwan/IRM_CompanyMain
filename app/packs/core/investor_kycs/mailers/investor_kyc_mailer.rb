class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  def notify_kyc_updated
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_kyc, @user.email)

    if email.present?
      subj = "KYC updated for #{@investor_kyc.full_name}"
      mail(from: from_email(@investor_kyc.entity),
           to: email,
           subject: subj)
    end
  end
end
