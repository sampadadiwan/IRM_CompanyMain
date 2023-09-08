class InvestorAccessNotification < BaseNotification
  # Add your delivery methods

  if Rails.env.test?
    deliver_by :email, mailer: "InvestorAccessMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "InvestorAccessMailer", method: :email_method, format: :email_data, delay: :email_delay
  end

  # Add required params
  param :investor_access

  def email_data
    {
      user_id: recipient.id,
      investor_access_id: params[:investor_access].id,
      entity_id: params[:entity_id]
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
