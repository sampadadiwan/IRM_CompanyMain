class InvestorKycMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_kyc_required
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    email = sandbox_email(@investor_access, @investor_access.email)

    subj = "Please complete your KYC for #{@investor_access.entity_name}"
    mail(from: from_email(@investor_access.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end

  def notify_kyc_updated
    @investor_kyc = InvestorKyc.find(params[:id])
    @investor_accesses = @investor_kyc.entity.investor_accesses.joins(:investor).where("investors.category='Advisor'")

    to_emails = [@investor_kyc.user.email] + @investor_accesses.collect(&:email)

    email = sandbox_email(@investor_kyc, to_emails)

    subj = "KYC updated for #{@investor_kyc.user.full_name}"
    mail(from: from_email(@investor_kyc.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end
end
