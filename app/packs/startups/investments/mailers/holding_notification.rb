class HoldingNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "HoldingMailer", method: :email_method, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :holding_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      holding_id: params[:holding_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @holding = Holding.find(params[:holding_id])
    params[:msg] || "Holding: #{@holding}"
  end

  def url
    holding_path(id: params[:holding_id])
  end
end
