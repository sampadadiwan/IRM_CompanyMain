class CapitalDistributionPaymentNotifier < BaseNotifier
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
      capital_distribution_payment_id: record.id,
      additional_ccs: record.capital_commitment.cc
    }
  end

  notification_methods do
    def message
      @capital_distribution_payment = record
      params[:msg] || "CapitalDistributionPayment: #{@capital_distribution_payment}"
    end

    def custom_notification
      nil
    end

    def url
      capital_distribution_payment_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
