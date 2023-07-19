# To deliver this notification:
#
# DocumentNotification.with(document_id: @document.id, msg: "Please View").deliver_later(current_user)
# DocumentNotification.with(document_id: @document.id, msg: "Please View").deliver(current_user)

class DocumentNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "DocumentMailer", method: :notify_new_document, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :document_id

  def email_data
    {
      user_id: recipient.id,
      document_id: params[:document_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @document = Document.find(params[:document_id])
    params[:msg] || "Document Uploaded: #{@document.name}"
  end

  def url
    document_path(id: params[:document_id])
  end
end
