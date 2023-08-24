class CapitalDistributionPaymentNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "CapitalDistributionPaymentsMailer", method: :send_notification, format: :email_data

  # Add required params
  param :capital_distribution_payment

  def email_data
    {
      user_id: recipient.id,
      capital_distribution_payment_id: params[:capital_distribution_payment].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @capital_distribution_payment = params[:capital_distribution_payment]
    params[:msg] || "CapitalDistributionPayment: #{@capital_distribution_payment}"
  end

  def url
    capital_distribution_payment_path(id: params[:capital_distribution_payment].id)
  end
end
