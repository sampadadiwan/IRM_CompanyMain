class CapitalDistributionPaymentNotifier < BaseNotifier
  # Add required params
  required_param :capital_distribution_payment

  def mailer_name(_notification = nil)
    CapitalDistributionPaymentsMailer
  end

  def email_method(_notification = nil)
    :send_notification
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_distribution_payment_id: params[:capital_distribution_payment].id,
      additional_ccs: params[:capital_distribution_payment].capital_commitment.cc
    }
  end

  notification_methods do
    def message
      @capital_distribution_payment = params[:capital_distribution_payment]
      params[:msg] || "CapitalDistributionPayment: #{@capital_distribution_payment}"
    end

    def custom_notification
      nil
    end

    def url
      capital_distribution_payment_path(id: params[:capital_distribution_payment].id, sub_domain: params[:capital_distribution_payment].entity.sub_domain)
    end
  end
end
