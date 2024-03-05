class InvestorKycNotification < BaseNotification
  # Add required params
  params :investor_kyc

  def mailer_name
    InvestorKycMailer
  end

  def email_data
    {
      notification_id: record.id,
      user_id: recipient.id,
      investor_kyc_id: params[:investor_kyc].id,
      entity_id: params[:entity_id],
      message:
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investor_kyc ||= params[:investor_kyc]
    @custom_notification = @investor_kyc.entity.custom_notification(email_method)
    @custom_notification&.whatsapp || params[:msg]
  end

  def url
    investor_kyc_url(id: params[:investor_kyc].id)
  end
end
