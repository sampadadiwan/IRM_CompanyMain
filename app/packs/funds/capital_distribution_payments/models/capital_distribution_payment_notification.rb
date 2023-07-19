# To deliver this notification:
#
# CapitalDistributionPaymentNotification.with(capital_distribution_payment_id: @capital_distribution_payment.id, msg: "Please View").deliver_later(current_user)
# CapitalDistributionPaymentNotification.with(capital_distribution_payment_id: @capital_distribution_payment.id, msg: "Please View").deliver(current_user)

class CapitalDistributionPaymentNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "CapitalDistributionPaymentsMailer", method: :send_notification, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :capital_distribution_payment_id

  def email_data
    {
      user_id: recipient.id,
      capital_distribution_payment_id: params[:capital_distribution_payment_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @capital_distribution_payment = CapitalDistributionPayment.find(params[:capital_distribution_payment_id])
    params[:msg] || "CapitalDistributionPayment: #{@capital_distribution_payment}"
  end

  def url
    capital_distribution_payment_path(id: params[:capital_distribution_payment_id])
  end
end
