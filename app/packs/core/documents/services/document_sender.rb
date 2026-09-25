class DocumentSender
  def self.send(document, _user_id, custom_notification_id)
    # If the document is subject to approval and is approved only then send it
    if (document.subject_to_approval? && document.approved) || !document.subject_to_approval?
      # Resolve recipients once: notification_users walks every access right and runs a policy
      # per contact, so evaluating it for present? and again for each doubled the cost.
      users = document.notification_users

      # Stop the whole send before fanning out if anything it would attach is too big.
      # DocumentMailer#send_document attaches the document itself, and send_mail adds the
      # CustomNotification's own documents on top, so both count toward the one email.
      # (attachment_names contributes nothing here - custom_notification_documents_owner is
      # the Document, which has no `documents` association.) Raising matches the existing
      # guards below; both callers already turn it into operator-visible feedback.
      # Resolved the same way DocumentMailer#set_document does, so the preflight counts the
      # same CustomNotification documents the send will attach. find_by(id: nil) would return
      # nil and quietly miss them whenever no explicit id was passed.
      custom_notification = document.entity.custom_notification("send_document", custom_notification_id:)
      attachable = [document] + (custom_notification ? custom_notification.documents.to_a : [])
      oversize = NotificationAttachmentPreflight.error_message(attachable, context: "Cannot send #{document.name}")
      raise StandardError, oversize if oversize

      if users.present?
        users.each do |user|
          DocumentNotifier.with(record: document,
                                entity_id: document.entity_id,
                                email_method: "send_document",
                                custom_notification_id:).deliver(user)
        rescue StandardError => e
          msg = "Error sending #{document.name} to #{user.email} #{e.message}"
          Rails.logger.error(msg)
          raise StandardError, msg
        end
      else
        msg = "No users to send #{document.name} #{document.id} to"
        Rails.logger.error(msg)
        raise StandardError, msg
      end

    else
      msg = "Document #{document.name} is not approved" unless document.approved
      msg = "Document #{document.name} does not belong to KYC or Commitment" unless %w[InvestorKyc CapitalCommitment IndivdualKyc NonIndivdualKyc].include?(document.owner_type)
      Rails.logger.error(msg)
      raise StandardError, msg
    end
  end
end
