class ApprovalNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    ApprovalMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      approval_response_id: record.id,
      investor_id: params[:investor_id]
    }
  end

  notification_methods do
    def model
      record
    end

    def message
      @approval_response ||= record
      @approval ||= @approval_response.approval
      @custom_notification ||= custom_notification
      @custom_notification&.subject.presence || params[:msg].presence || @approval&.title
    end

    def custom_notification
      @approval_response ||= record
      @approval ||= @approval_response.approval
      @custom_notification ||= @approval.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      @approval ||= record.approval
      if params[:email_method]&.to_s == "notify_approval_response"
        approval_response_path(id: record.id, sub_domain: @approval.entity.sub_domain)
      else
        approval_path(@approval, sub_domain: @approval.entity.sub_domain)
      end
    end
  end
end
