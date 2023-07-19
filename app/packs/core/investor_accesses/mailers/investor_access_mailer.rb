class InvestorAccessMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_access, @user.email)

    subj = "Access Granted to #{@investor_access.entity_name}"
    mail(from: from_email(@investor_access.entity), to: email,
         subject: subj)
  end

  def notify_kyc_required
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_access, @user.email)

    if email.present?
      subj = "Please complete your KYC for #{@investor_access.entity_name}"
      mail(from: from_email(@investor_access.entity),
           to: email,
           subject: subj)
    end
  end
end
