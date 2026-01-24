class FundCommitmentNotifier < BaseNotifier
  required_param :email_method
  required_param :custom_notification_id

  def mailer_name(_notification = nil)
    CapitalCommitmentMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      capital_commitment_id: record.id,
      investor_id: record.investor_id,
      from_email: record.fund.custom_fields.from_email,
      custom_notification_id: params[:custom_notification_id]
    }
  end

  notification_methods do
    def message
      @commitment = record
      @custom_notification ||= custom_notification
      params[:msg] || "Notification for: #{@commitment}"
    end

    def custom_notification
      @custom_notification = CustomNotification.find(params[:custom_notification_id])
    end

    def url
      capital_commitment_url(record, sub_domain: record.entity.sub_domain)
    end
  end
end
