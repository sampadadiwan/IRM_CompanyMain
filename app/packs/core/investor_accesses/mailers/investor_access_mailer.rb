class InvestorAccessMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    email = sandbox_email(@investor_access, @investor_access.email)

    subj = "Access Granted to #{@investor_access.entity_name}"
    mail(from: from_email(@investor_access.entity), to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)

    msg = "Access Granted to #{@investor_access.entity_name} to #{ENV['DOMAIN']}. Please login to view details."
    WhatsappSenderJob.new.perform(msg, @investor_access.user) if @investor_access.user
  end
end
