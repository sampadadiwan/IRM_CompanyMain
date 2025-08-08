class InvestorKycNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    InvestorKycMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      investor_kyc_id: record.id,
      entity_id: params[:entity_id],
      message: notification.message,
      investor_advisor_id: investor_advisor_id(record.investor.investor_entity_id, notification.recipient_id)
    }
  end

  notification_methods do
    def message
      @investor_kyc ||= record
      @custom_notification ||= custom_notification
      @custom_notification&.subject || params[:msg]
    end

    def custom_notification
      @investor_kyc ||= record
      @custom_notification ||= @investor_kyc.entity.custom_notification(params[:email_method])
      @custom_notification
    end

    def url
      if %i[notify_kyc_required kyc_required_reminder].include? params[:email_method]
        edit_investor_kyc_path(id: record.id, sub_domain: record.entity.sub_domain)
      else
        investor_kyc_path(id: record.id, sub_domain: record.entity.sub_domain)
      end
    end
  end
end
