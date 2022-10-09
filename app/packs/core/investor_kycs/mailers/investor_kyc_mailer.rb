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

    WhatsappSenderJob.new.perform(subj, @investor_access.user) if @investor_access.user
  end
end
