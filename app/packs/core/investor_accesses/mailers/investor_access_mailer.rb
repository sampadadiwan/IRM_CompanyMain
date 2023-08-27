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

  def notify_kyc_required
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_access, @user.email)

    if email.present?
      subj = "Request to add KYC: #{@investor_access.entity_name}"
      mail(from: from_email(@investor_access.entity),
           to: email,
           cc: @investor_access.entity.entity_setting.cc,
           subject: subj)
    end
  end

  def kyc_required_reminder
    @investor_access = InvestorAccess.includes(:user).find params[:investor_access_id]
    @user = User.find(params[:user_id])
    email = sandbox_email(@investor_access, @user.email)

    if email.present?
      subj = "Reminder to update KYC: #{@investor_access.entity_name}"
      mail(from: from_email(@investor_access.entity),
           to: email,
           cc: @investor_access.entity.entity_setting.cc,
           subject: subj)
    end
  end
end
