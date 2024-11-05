class DocumentsBulkActionJob < BulkActionJob
  def perform_action(document, user_id, bulk_action, params: {})
    msg = "#{bulk_action}: #{document.name}"
    send_notification(msg, user_id, :success)

    case bulk_action.downcase

    when "send document"
      send_document(document, user_id, params[:custom_notification_id])

    when "delete"
      if document.owner_tag == "Signed"
        msg = "Document #{document.name} is signed document, it cannot be deleted."
        set_error(msg, document, user_id)
      else
        document.destroy
      end

    when "approve"
      user = User.find(user_id)
      if Pundit.policy(user, document).approve?
        document.update(approved: true, approved_by_id: user_id)
      else
        msg = if document.approved
                "Document #{document.name} is already approved."
              elsif document.subject_to_approval?
                "Document #{document.name} is not generated, does not require approval."
              elsif !user.has_cached_role?(:approver)
                "User #{user.email} does not have permission to approve document #{document.name}."
              else
                "Document #{document.name} is not ready for approval."
              end
        set_error(msg, document, user_id)
      end

    when "send for esignatures"
      if document.to_be_esigned?
        EsignJob.set(wait: rand(15).seconds).perform_later(document.id, user_id)
        sleep(1) # This is so that we dont flood Digio/Docusign, throttle requests sent
      else
        msg = "Document #{document.name} is not ready for eSignature"
        set_error(msg, document, user_id)
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)

    end
  end

  def get_class
    Document
  end

  def send_document(document, user_id, custom_notification_id)
    DocumentSender.send(document, user_id, custom_notification_id)
  rescue StandardError => e
    set_error(e.message, document, user_id)
  end

  def set_error(msg, document, user_id)
    Rails.logger.error(msg)
    send_notification(msg, user_id, "danger")
    @error_msg << { msg:, document: document.name, document_id: document.id, for: document.owner }
  end
end
