class ApprovalNotification < BaseNotification
  # Add your delivery methods
  if Rails.env.test?
    deliver_by :email, mailer: "ApprovalMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "ApprovalMailer", method: :email_method, format: :email_data, delay: :email_delay
  end

  # Add required params
  param :approval_response
  param :email_method

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
    params[:msg] || "Approval: #{@approval_response.approval.title}"
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
