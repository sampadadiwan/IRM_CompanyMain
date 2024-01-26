class HoldingNotification < BaseNotification
  # Add required params
  param :holding
  param :email_method

  def mailer_name
    HoldingMailer
  end

  def email_data
    {
      notification_id: record.id,
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
