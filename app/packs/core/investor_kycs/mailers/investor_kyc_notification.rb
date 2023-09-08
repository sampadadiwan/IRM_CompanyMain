class InvestorKycNotification < BaseNotification
  # Add your delivery methods
  if Rails.env.test?
    deliver_by :email, mailer: "InvestorKycMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "InvestorKycMailer", method: :email_method, format: :email_data, delay: :email_delay
  end

  # Add required params
  params :investor_kyc

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
