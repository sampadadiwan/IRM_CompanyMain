class CapitalDistributionPaymentNotification < BaseNotification
  # Add required params
  param :capital_distribution_payment

  def mailer_name
    CapitalDistributionPaymentsMailer
  end

  def email_method
    :send_notification
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      capital_distribution_payment_id: params[:capital_distribution_payment].id,
      additional_ccs: params[:capital_distribution_payment].capital_commitment.cc
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
