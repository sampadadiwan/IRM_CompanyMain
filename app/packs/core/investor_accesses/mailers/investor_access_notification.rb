class InvestorAccessNotification < BaseNotification
  # Add required params
  param :investor_access

  def mailer_name
    InvestorAccessMailer
  end

  def email_data
    {
      notification_id: record.id,
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
