# To deliver this notification:
#
# DocumentDownloadNotification.with(document_id: @document.id, msg: "Please download").deliver_later(current_user)
# DocumentDownloadNotification.with(document_id: @document.id, msg: "Please download").deliver(current_user)

class DocumentDownloadNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "DocumentMailer", method: :email_link, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", delay: 5.seconds
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :document_id
  param :msg

  def email_data
    {
      user_id: recipient.id,
      document_id: params[:document_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    params[:msg]
  end

  def url
    document_path(id: params[:document_id])
  end
end
