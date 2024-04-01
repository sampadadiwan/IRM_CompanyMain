class ApprovalNotifier < BaseNotifier
  # Add required params
  required_param :approval_response
  required_param :email_method

  def mailer_name(_notification = nil)
    ApprovalMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      approval_response_id: params[:approval_response].id
    }
  end

  notification_methods do
    def message
      @approval_response = params[:approval_response]
      @approval = @approval_response.approval
      @custom_notification = @approval.custom_notification(params[:email_method])
      @custom_notification&.whatsapp.presence || params[:msg].presence || @approval.title
    end

    def url
      @approval ||= params[:approval_response].approval
      if params[:email_method]&.to_s == "notify_approval_response"
        approval_response_path(id: params[:approval_response].id)
      else
        approval_path(@approval, subdomain: @approval.entity.sub_domain)
      end
    end
  end
end
