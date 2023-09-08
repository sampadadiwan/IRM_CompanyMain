class HoldingNotification < BaseNotification
  # Add your delivery methods
  if Rails.env.test?
    deliver_by :email, mailer: "HoldingMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "HoldingMailer", method: :email_method, format: :email_data, delay: :email_delay
  end
  # Add required params
  param :holding
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      holding_id: params[:holding].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @holding = params[:holding]
    params[:msg] || "Holding: #{@holding}"
  end

  def url
    holding_path(id: params[:holding].id)
  end
end
