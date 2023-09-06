class ApprovalMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_approval
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @approval = @approval_response.approval
    if @approval_response.status == "Pending"

      if @to.present?
        # Mark notification_sent as true
        @approval_response.update_column(:notification_sent, true)
        send_mail(subject: "Approval required for #{@approval.entity.name}: #{@approval.title}")

      end
    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
  end

  def approval_reminder
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @approval = @approval_response.approval

    if @approval_response.status == "Pending"

      if @to.present?
        # Mark notification_sent as true
        @approval_response.update_column(:notification_sent, true)
        send_mail(subject: "Reminder for approval required for #{@approval.entity.name}: #{@approval.title}")

      end
    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
  end

  def notify_approval_response
    @approval_response = ApprovalResponse.find params[:approval_response_id]

    send_mail(subject: "#{@approval_response.entity.name}: #{@approval_response.status} for #{@approval_response.approval.title}") if @to.present?
  end
end
