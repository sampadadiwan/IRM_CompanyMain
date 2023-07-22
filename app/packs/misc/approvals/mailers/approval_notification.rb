# To deliver this notification:
#
# ApprovalNotification.with(approval_id: @approval.id, msg: "Please View").deliver_later(current_user)
# ApprovalNotification.with(approval_id: @approval.id, msg: "Please View").deliver(current_user)

class ApprovalNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "ApprovalMailer", method: :email_method, format: :email_data

  # Add required params
  param :approval_response_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      approval_response_id: params[:approval_response_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @approval_response = ApprovalResponse.find(params[:approval_response_id])
    params[:msg] || "Approval: #{@approval_response.approval.title}"
  end

  def url
    approval_response_path(id: params[:approval_response_id])
  end
end
