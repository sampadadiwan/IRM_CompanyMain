class DocumentNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    DocumentMailer
  end

  def email_method(_notification = nil)
    params[:email_method] || :notify_new_document
  end

  def email_data(notification)
    fund_id = record.owner.fund_id if record.owner.respond_to?(:fund_id)
    fund_id ||= record.fund_id if record.respond_to?(:fund_id)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      document_id: record.id,
      entity_id: params[:entity_id],
      fund_id: fund_id
    }
  end

  notification_methods do
    def message
      @document = record
      @custom_notification ||= custom_notification
      @custom_notification&.subject || params[:msg] || "Document Uploaded: #{@document&.name}"
    end

    def custom_notification
      @document ||= record
      @custom_notification ||= @document&.entity&.custom_notification(params[:email_method], custom_notification_id: params[:custom_notification_id])
      @custom_notification
    end

    def url
      document_path(id: record, sub_domain: record.entity.sub_domain)
    end
  end
end
