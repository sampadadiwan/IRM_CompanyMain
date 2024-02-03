class DocumentsBulkActionJob < BulkActionJob
  def perform_action(document, user_id, bulk_action)
    msg = "#{bulk_action}: #{document.name}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase
    when "send commitment agreement"
      if document.approved && %w[InvestorKyc CapitalCommitment IndivdualKyc NonIndivdualKyc].include?(document.owner_type)

        document.notification_users.each do |user|
          DocumentNotification.with(entity_id: document.entity_id,
                                    document:, email_method: "send_commitment_agreement",
                                    custom_notification_for: "Commitment Agreement").deliver(user)
        rescue Exception => e
          msg = "Error sending #{document.name} to #{user.email} #{e.message}"
          send_notification(msg, user_id, "danger")
          @error_msg << { msg:, document: document.name, document_id: document.id, for: document.owner }
        end

      else
        msg = "Document #{document.name} is not approved" unless document.approved
        msg = "Document #{document.name} is not a commitment agreement" unless %w[InvestorKyc CapitalCommitment].include?(document.owner_type)
        send_notification(msg, user_id, "danger")
        @error_msg << { msg:, document: document.name, document_id: document.id, for: document.owner }
      end

    when "approve"
      document.update(approved: true, approved_by_id: user_id) if document.to_be_approved?

    when "send for esignatures"
      DigioEsignJob.perform_now(document.id, user_id) if document.to_be_esigned?
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end

  def get_class
    Document
  end
end
