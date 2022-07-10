class InvestorAccessMailer < ApplicationMailer
  helper ApplicationHelper
  
  def notify_access
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]

    subj = "Access Granted to #{@investor_access.entity_name}"
    mail(to: @investor_access.email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)

    msg = "Access Granted to #{@investor_access.entity_name} to #{ENV['DOMAIN']}. Please login to view details."
    WhatsappSenderJob.new.perform(msg, @investor_access.user) if @investor_access.user
  end
end
