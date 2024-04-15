class DocumentDownloadNotifier < BaseNotifier
  # Add required params
  required_param :document
  required_param :msg

  def mailer_name(_notification = nil)
    DocumentMailer
  end

  def email_method(_notification = nil)
    :email_link
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
      params[:msg]
    end

    def custom_notification
      nil
    end

    def url
      document_path(id: params[:document].id)
    end
  end
end
