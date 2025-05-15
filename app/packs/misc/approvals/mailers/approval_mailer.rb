class ApprovalMailer < ApplicationMailer
  helper ApplicationHelper

  before_action :set_approval
  def set_approval
    @approval_response = ApprovalResponse.find params[:approval_response_id]
    @approval = @approval_response.approval
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @approval.custom_notification(email_method)
  end

  def attach_all_docs
    # Check for attachments
    @approval.documents.each do |doc|
      # This password protects the file if required and attachs it
      pw_protect_attach_file(doc, @custom_notification)
    end
  end

  def update_notification_sent(subject)
    if @approval_response.status == "Pending"

      if @to.present?
        # Mark notification_sent as true
        @approval_response.update_column(:notification_sent, true) if @notification
        send_mail(subject:)
      end
    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
  end

  def notify_new_approval
    subject = "Approval required for #{@approval.entity.name}: #{@approval.title}"
    attach_all_docs
    update_notification_sent(subject)
  end

  def approval_reminder
    subject = "Approval required for #{@approval.entity.name}: #{@approval.title}"
    attach_all_docs
    update_notification_sent(subject)
  end

  def notify_approval_response
    subject = "#{@approval_response.entity.name}: #{@approval_response.status} for #{@approval_response.approval.title}"

    send_mail(subject:)
  end
end
