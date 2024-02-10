class DocumentsBulkActionJob < BulkActionJob
  def perform_action(document, user_id, bulk_action)
    msg = "#{bulk_action}: #{document.name}"
    send_notification(msg, user_id, :success)
    
    case bulk_action.downcase

    when "send commitment agreement"
      send_commitment_agreement(document, user_id)

    when "approve"
      if document.to_be_approved?
        document.update(approved: true, approved_by_id: user_id)
      else
        msg = "Document #{document.name} is not ready for approval"
        set_error(msg, document, user_id)
      end

    when "send for esignatures"
      if document.to_be_esigned?
        DigioEsignJob.perform_now(document.id, user_id)
      else
        msg = "Document #{document.name} is not ready for e-signature"
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

  def send_commitment_agreement(document, user_id)
    if document.approved && %w[InvestorKyc CapitalCommitment IndivdualKyc NonIndivdualKyc].include?(document.owner_type)

      document.notification_users.each do |user|
        DocumentNotification.with(entity_id: document.entity_id,
                                  document:, email_method: "send_commitment_agreement",
                                  custom_notification_for: "Commitment Agreement").deliver(user)
      rescue Exception => e
        msg = "Error sending #{document.name} to #{user.email} #{e.message}"
        set_error(msg, document, user_id)
      end

    else
      msg = "Document #{document.name} is not approved" unless document.approved
      msg = "Document #{document.name} is not a commitment agreement" unless %w[InvestorKyc CapitalCommitment].include?(document.owner_type)
      set_error(msg, document, user_id)
    end
  end

  def set_error(msg, document, user_id)
    send_notification(msg, user_id, "danger")
    @error_msg << { msg:, document: document.name, document_id: document.id, for: document.owner }
  end
end
