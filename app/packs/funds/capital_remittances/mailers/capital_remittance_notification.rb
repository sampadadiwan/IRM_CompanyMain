class CapitalRemittanceNotification < BaseNotification
  # Add required params
  param :capital_remittance
  param :email_method

  def mailer_name
    CapitalRemittanceMailer
  end

  def email_data
    {
      notification_id: record.id,
      user_id: recipient.id,
      entity_id: params[:entity_id],
      capital_remittance_id: params[:capital_remittance].id,
      additional_ccs: params[:capital_remittance].capital_commitment.cc
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @capital_remittance = params[:capital_remittance]
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification(email_method)

    @custom_notification&.whatsapp || params[:msg].presence || "Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}"
  end

  def url
    capital_remittance_path(id: params[:capital_remittance].id)
  end
end
