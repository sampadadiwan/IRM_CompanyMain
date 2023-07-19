class InvestorKycNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "InvestorKycMailer", method: :email_method, format: :email_data

  # Add required params
  params :investor_kyc_id

  def email_data
    {
      user_id: recipient.id,
      investor_kyc_id: params[:investor_kyc_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investor_kyc ||= InvestorKyc.find(params[:investor_kyc_id])
    params[:msg] || "Kyc #{params[:type]}: #{@investor_kyc.full_name}"
  end

  def url
    # @investor_kyc ||= InvestorKyc.find(params[:investor_kyc_id])
    investor_kyc_url(id: params[:investor_kyc_id])
  end
end
