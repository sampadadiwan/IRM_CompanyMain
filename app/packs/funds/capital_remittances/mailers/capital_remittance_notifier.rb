class CapitalRemittanceNotifier < BaseNotifier
  # Add required params
  required_param :capital_remittance
  required_param :email_method

  def mailer_name(_notification = nil)
    CapitalRemittanceMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_remittance_id: params[:capital_remittance].id,
      additional_ccs: params[:capital_remittance].capital_commitment.cc
    }
  end

  notification_methods do
    def message
      @capital_remittance = params[:capital_remittance]
      @capital_call = @capital_remittance.capital_call
      @custom_notification = @capital_call.custom_notification(params[:email_method])

      @custom_notification&.whatsapp || params[:msg].presence || "Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}"
    end

    def url
      capital_remittance_path(id: params[:capital_remittance].id)
    end
  end
end
