class InvestorKycNotification < BaseNotification
  # Add required params
  params :investor_kyc

  def mailer_name
    InvestorKycMailer
  end

  def email_data
    {
      user_id: recipient.id,
      investor_kyc_id: params[:investor_kyc].id,
      entity_id: params[:entity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investor_kyc ||= params[:investor_kyc]
    params[:msg] || "Kyc #{params[:type]}: #{@investor_kyc.full_name}"
  end

  def url
    investor_kyc_url(id: params[:investor_kyc].id)
  end
end
