class DocumentNotification < BaseNotification
  # Add required params
  param :document

  def mailer_name
    DocumentMailer
  end

  def email_method
    params[:email_method] || :notify_new_document
  end

  def email_data
    {
      user_id: recipient.id,
      document_id: params[:document].id,
      entity_id: params[:entity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @document = params[:document]
    @custom_notification = @document.entity.custom_notification(params[:custom_notification_for])
    @custom_notification&.whatsapp || params[:msg] || "Document Uploaded: #{@document.name}"
  end

  def url
    document_path(id: params[:document])
  end
end
