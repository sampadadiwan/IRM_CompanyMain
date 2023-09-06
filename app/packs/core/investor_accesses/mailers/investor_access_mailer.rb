class InvestorAccessMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]

    subj = "Access Granted to #{@investor_access.entity_name}"
    send_mail(subject: subj)
  end
end
