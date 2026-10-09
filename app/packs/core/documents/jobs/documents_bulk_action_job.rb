class DocumentsBulkActionJob < BulkActionJob
  # Runs the bulk action, then re-checks once per affected call or distribution (not once per
  # document) when their notices were approved.
  # Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples E18 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def perform(record_ids, user_id, bulk_action, params: {})
    result = super
    if bulk_action.to_s.downcase == "approve"
      Document.notices_journey_progress!(Document.notice_journey_ids(Document.where(id: record_ids)),
                                         actor: User.find_by(id: user_id))
    end
    result
  end

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
      elsif !document.approved
        msg = "Document #{document.name} is not approved."
        set_error(msg, document, user_id)
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
