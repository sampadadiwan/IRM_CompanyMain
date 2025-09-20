class CapitalRemittancePaymentNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    CapitalRemittancePaymentMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_remittance_payment_id: record.id,
      fund_id: record.fund_id,
      from_email: record.fund.custom_fields.from_email,
      additional_ccs: record.capital_remittance.capital_commitment.cc,
      investor_id: record.capital_remittance.investor_id,
      investor_advisor_id: investor_advisor_id(record.investor.investor_entity_id, notification.recipient_id)
    }
  end

  notification_methods do
    def message
      @capital_remittance_payment ||= record
      @capital_remittance ||= @capital_remittance_payment.capital_remittance
      @capital_call ||= @capital_remittance.capital_call
      @custom_notification = custom_notification

      @custom_notification&.subject || params[:msg].presence || "Remittance payment received by #{@capital_remittance&.fund&.name} for #{@capital_remittance&.capital_call&.name}"
    end

    def custom_notification
      @capital_remittance_payment ||= record
      @capital_remittance ||= @capital_remittance_payment.capital_remittance
      @capital_call ||= @capital_remittance.capital_call
      @custom_notification ||= @capital_call.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      capital_remittance_payment_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
