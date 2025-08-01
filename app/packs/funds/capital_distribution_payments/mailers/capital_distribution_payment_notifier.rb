class CapitalDistributionPaymentNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    CapitalDistributionPaymentsMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_distribution_payment_id: record.id,
      fund_id: record.fund_id,
      from_email: record.fund.custom_fields.from_email,
      additional_ccs: record.capital_commitment.cc
    }
  end

  notification_methods do
    def message
      @capital_distribution_payment = record
      @custom_notification = custom_notification
      @custom_notification&.subject || params[:msg].presence || "CapitalDistributionPayment: #{@capital_distribution_payment}"
    end

    def custom_notification
      @capital_distribution_payment ||= record
      @capital_distribution ||= @capital_distribution_payment.capital_distribution
      @custom_notification ||= @capital_distribution.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      capital_distribution_payment_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
