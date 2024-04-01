class InvestorKycNotifier < BaseNotifier
  # Add required params
  required_params :investor_kyc

  def mailer_name(_notification = nil)
    InvestorKycMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      investor_kyc_id: params[:investor_kyc].id,
      entity_id: params[:entity_id],
      message: notification.message
    }
  end

  notification_methods do
    def message
      @investor_kyc ||= params[:investor_kyc]
      @custom_notification = @investor_kyc.entity.custom_notification(params[:email_method])
      @custom_notification&.whatsapp || params[:msg]
    end

    def url
      investor_kyc_path(id: params[:investor_kyc].id)
    end
  end
end
