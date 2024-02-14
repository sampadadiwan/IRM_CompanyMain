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
    if email_method.to_s == "notify_kyc_required" || email_method.to_s == "kyc_required_reminder"
      @investor_kyc ||= params[:investor_kyc]
      @custom_notification = @investor_kyc.entity.custom_notification("InvestorKyc")
      @custom_notification&.whatsapp || params[:msg]
    else
      params[:msg]
    end
  end

  def url
    investor_kyc_url(id: params[:investor_kyc].id)
  end
end
