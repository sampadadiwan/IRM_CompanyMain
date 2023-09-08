class InterestNotification < BaseNotification
  # Add your delivery methods
  if Rails.env.test?
    deliver_by :email, mailer: "InterestMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "InterestMailer", method: :email_method, format: :email_data, delay: :email_delay
  end

  # Add required params
  param :interest
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      interest_id: params[:interest].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @interest = params[:interest]
    params[:msg] || "Interest: #{@interest}"
  end

  def url
    interest_path(id: params[:interest].id)
  end
end
