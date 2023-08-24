class DocumentDownloadNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "DocumentMailer", method: :email_link, format: :email_data

  # Add required params
  param :document
  param :msg

  def email_data
    {
      user_id: recipient.id,
      document_id: params[:document].id
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
