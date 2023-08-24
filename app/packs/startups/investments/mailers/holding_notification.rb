class HoldingNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "HoldingMailer", method: :email_method, format: :email_data

  # Add required params
  param :holding
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
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
