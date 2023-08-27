class ApprovalMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_approval
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @approval = @approval_response.approval
    @user = User.find params[:user_id]

    if @approval_response.status == "Pending"
      # Get all emails of investors
      investor_emails = sandbox_email(@approval_response,
                                      @user.email)

      if investor_emails.present?
        # Mark notification_sent as true
        @approval_response.update_column(:notification_sent, true)
        mail(from: from_email(@approval.entity),
             to: investor_emails,
             cc: @approval_response.entity.entity_setting.cc,
             reply_to: @approval_response.entity.entity_setting.cc,
             subject: "Approval required for #{@approval.entity.name}: #{@approval.title}")

      end
    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
  end

  def approval_reminder
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @approval = @approval_response.approval
    @user = User.find params[:user_id]

    if @approval_response.status == "Pending"
      # Get all emails of investors
      investor_emails = sandbox_email(@approval_response,
                                      @user.email)

      if investor_emails.present?
        # Mark notification_sent as true
        @approval_response.update_column(:notification_sent, true)
        mail(from: from_email(@approval.entity),
             to: investor_emails,
             cc: @approval_response.entity.entity_setting.cc,
             reply_to: @approval_response.entity.entity_setting.cc,
             subject: "Reminder for approval required for #{@approval.entity.name}: #{@approval.title}")

      end
    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
  end

  def notify_approval_response
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @user = User.find params[:user_id]

    # Get all emails of investors
    investor_emails = sandbox_email(@approval_response,
                                    @user.email)

    cc_emails = @approval_response.entity.employees.collect(&:email) << @approval_response.entity.entity_setting.cc

    employee_emails = sandbox_email(@approval_response, cc_emails.compact.join(","))

    if investor_emails.present?
      mail(from: from_email(@approval_response.entity),
           to: investor_emails,
           cc: employee_emails,
           reply_to: employee_emails,
           subject: "#{@approval_response.entity.name}: #{@approval_response.status} for #{@approval_response.approval.title}")
    end
  end
end
