class InvestorAccessNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "InvestorAccessMailer", method: :email_method, format: :email_data

  # Add required params
  param :investor_access_id

  def email_data
    {
      user_id: recipient.id,
      investor_access_id: params[:investor_access_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investor_access ||= InvestorAccess.find(params[:investor_access_id])
    params[:msg] || "Access granted to #{@investor_access.entity.name}"
  end

  def url
    # @investor_access ||= InvestorAccess.find(params[:investor_access_id])
    investor_access_url(id: params[:investor_access_id])
  end
end
