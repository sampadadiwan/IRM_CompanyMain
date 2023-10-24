class InterestNotification < BaseNotification
  # Add required params
  param :interest
  param :email_method

  def mailer_name
    InterestMailer
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
