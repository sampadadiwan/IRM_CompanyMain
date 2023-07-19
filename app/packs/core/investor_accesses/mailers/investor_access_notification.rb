class InvestorAccessNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "InvestorAccessMailer", method: :notify_access, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

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
