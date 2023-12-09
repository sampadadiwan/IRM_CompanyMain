class ApprovalNotification < BaseNotification
  # Add required params
  param :approval_response
  param :email_method

  def mailer_name
    ApprovalMailer
  end

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      approval_response_id: params[:approval_response].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @approval_response = params[:approval_response]
    @approval = @approval_response.approval
    @custom_notification = @approval.custom_notification
    @custom_notification&.whatsapp.presence || @approval.title
  end

  def url
    @approval ||= params[:approval_response].approval
    if email_method&.to_s == "notify_approval_response"
      approval_response_path(id: params[:approval_response].id)
    else
      approval_url(@approval, subdomain: @approval.entity.sub_domain)
    end
  end
end
