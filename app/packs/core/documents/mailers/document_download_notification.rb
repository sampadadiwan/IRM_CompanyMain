class DocumentDownloadNotification < BaseNotification
  # Add required params
  param :document
  param :msg

  def mailer_name
    DocumentMailer
  end

  def email_method
    :email_link
  end

  def email_data
    {
      notification_id: record.id,
      user_id: recipient.id,
      document_id: params[:document].id,
      entity_id: params[:entity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    params[:msg]
  end

  def url
    document_path(id: params[:document].id)
  end
end
