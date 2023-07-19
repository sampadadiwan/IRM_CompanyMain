class InterestNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "InterestMailer", method: :email_method, format: :email_data

  # Add required params
  param :interest_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      interest_id: params[:interest_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @interest = Interest.find(params[:interest_id])
    params[:msg] || "Interest: #{@interest}"
  end

  def url
    interest_path(id: params[:interest_id])
  end
end
