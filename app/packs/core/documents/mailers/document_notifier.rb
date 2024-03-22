class DocumentNotifier < BaseNotifier
  # Add required params
  required_param :document

  def mailer_name(_notification = nil)
    DocumentMailer
  end

  def email_method(_notification = nil)
    params[:email_method] || :notify_new_document
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      document_id: params[:document].id,
      entity_id: params[:entity_id]
    }
  end

  notification_methods do
    def message
      @document = params[:document]
      @custom_notification = @document.entity.custom_notification(params[:email_method])
      @custom_notification&.whatsapp || params[:msg] || "Document Uploaded: #{@document.name}"
    end

    def url
      document_path(id: params[:document])
    end
  end
end
