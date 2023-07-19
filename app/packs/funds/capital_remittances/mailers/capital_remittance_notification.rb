# To deliver this notification:
#
# CapitalRemittanceNotification.with(capital_remittance_id: @capital_remittance.id, msg: "Please View").deliver_later(current_user)
# CapitalRemittanceNotification.with(capital_remittance_id: @capital_remittance.id, msg: "Please View").deliver(current_user)

class CapitalRemittanceNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "CapitalRemittancesMailer", method: :email_method, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :capital_remittance_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      capital_remittance_id: params[:capital_remittance_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    params[:msg] || "Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}"
  end

  def url
    capital_remittance_path(id: params[:capital_remittance_id])
  end
end
