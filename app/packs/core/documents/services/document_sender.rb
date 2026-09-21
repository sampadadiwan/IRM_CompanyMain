class DocumentSender
  def self.send(document, _user_id, custom_notification_id)
    # If the document is subject to approval and is approved only then send it
    if (document.subject_to_approval? && document.approved) || !document.subject_to_approval?
      # Resolve recipients once: notification_users walks every access right and runs a policy
      # per contact, so evaluating it for present? and again for each doubled the cost.
      users = document.notification_users
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
