# Tells a signer, in the app and by email, that a document is waiting for their signature and it is their turn.
# record: the ESignature. Sent only through Document#notify_ready_signers. In-app + email only: there is
# deliberately no custom_notification, so the shared WhatsApp delivery in BaseNotifier never fires for it.
# openspec/changes/embedded-esign-digio — design card ⑨. Worked examples H9, H10, E29-E35.
class EsignSigningNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    EsignSigningMailer
  end

  def email_method(_notification = nil)
    :signature_requested
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      e_signature_id: record.id
    }
  end

  notification_methods do
    def model
      record
    end

    def message
      "Your signature is requested: #{record.document.name} from #{record.document.entity.name}"
    end

    def url
      sign_e_signature_path(record)
    end
  end
end
