class InvestorAccessNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "InvestorAccessMailer", method: :email_method, format: :email_data

  # Add required params
  param :investor_access

  def email_data
    {
      user_id: recipient.id,
      investor_access_id: params[:investor_access].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @investor_access ||= params[:investor_access]
    params[:msg] || "Access granted to #{@investor_access.entity.name}"
  end

  def url
    investor_access_url(id: params[:investor_access].id)
  end
end
