class ApprovalNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "ApprovalMailer", method: :email_method, format: :email_data

  # Add required params
  param :approval_response
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      approval_response_id: params[:approval_response].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @approval_response = params[:approval_response]
    params[:msg] || "Approval: #{@approval_response.approval.title}"
  end

  def url
    approval_response_path(id: params[:approval_response].id)
  end
end
