class CapitalRemittanceNotifier < BaseNotifier
  # Add required params
  required_param :email_method

  def mailer_name(_notification = nil)
    CapitalRemittanceMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_remittance_id: record.id,
      fund_id: record.fund_id,
      from_email: record.fund.custom_fields.from_email,
      additional_ccs: record.capital_commitment.cc,
      investor_advisor_id: investor_advisor_id(record.investor.investor_entity_id, notification.recipient_id)
    }
  end

  notification_methods do
    def message
      @capital_remittance ||= record
      @capital_call ||= @capital_remittance.capital_call
      @custom_notification = custom_notification

      @custom_notification&.subject || params[:msg].presence || "Capital Call by #{@capital_remittance&.entity&.name} : #{@capital_remittance&.capital_call&.name}"
    end

    def custom_notification
      @capital_remittance ||= record
      @capital_call ||= @capital_remittance.capital_call
      @custom_notification ||= @capital_call.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      capital_remittance_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
