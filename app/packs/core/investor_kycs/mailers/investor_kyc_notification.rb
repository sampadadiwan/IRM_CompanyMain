class InvestorKycNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "InvestorKycMailer", method: :mailer_method, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  params :type
  # One of these is mandatory
  # params :investor_kyc_id
  # params :investor_access_id

  def mailer_method
    if params[:type] == "Updated"
      :notify_kyc_updated
    elsif params[:type] == "Create"
      :notify_kyc_required
    else
      raise "Unkonwn type #{params[:type]}}"
    end
  end

  def email_data
    {
      user_id: recipient.id,
      investor_kyc_id: params[:investor_kyc_id],
      investor_access_id: params[:investor_access_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    if params[:type] == "Updated"
      @investor_kyc ||= InvestorKyc.find(params[:investor_kyc_id])
      params[:msg] || "Kyc #{params[:type]}: #{@investor_kyc.full_name}"
    elsif params[:type] == "Create"
      @investor_access ||= InvestorAccess.includes(:user).find(params[:investor_access_id])
      params[:msg] || "Kyc #{params[:type]}: #{@investor_access.user.full_name}"
    else
      raise "Unkonwn type #{params[:type]}}"
    end
  end

  def url
    # @investor_kyc ||= InvestorKyc.find(params[:investor_kyc_id])
    if params[:type] == "Updated"
      investor_kyc_url(id: params[:investor_kyc_id])
    elsif params[:type] == "Create"
      @investor_access ||= InvestorAccess.includes(:user).find(params[:investor_access_id])
      new_investor_kyc_url('investor_kyc[investor_id]': @investor_access.investor_id, 'investor_kyc[entity_id]': @investor_access.entity_id, 'investor_kyc[user_id]': @investor_access.user_id, subdomain: @investor_access.entity.sub_domain)
    else
      raise "Unkonwn type #{params[:type]}}"
    end
  end
end
