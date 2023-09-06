class InvestorAccessMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_access, @user.email)

    subj = "Access Granted to #{@investor_access.entity_name}"
    mail(from: from_email(@investor_access.entity), to: email,
         cc: @investor_access.entity.entity_setting.cc,
         subject: subj)
  end
end
