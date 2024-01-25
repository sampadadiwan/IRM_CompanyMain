class DocumentsBulkActionJob < ApplicationJob
  queue_as :low

  # This is called every day at 2:01 am for all docs created in the last 10 days
  # to update the status of the e-signing process
  # Or it can be called with a document_id to update a single document
  def perform(document_ids, user_id, bulk_action)
    @error_msg = []

    Chewy.strategy(:sidekiq) do
      docs = Document.where(id: document_ids)
      docs.each do |doc|
        perform_action(doc, user_id, bulk_action)
      end
    end

    sleep(5)
    if @error_msg.present?
      msg = "#{bulk_action} completed for #{document_ids.count} documents, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :error)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      msg = "#{bulk_action} completed for #{document_ids.count} documents"
      send_notification(msg, user_id, :success)
    end
  end

  def perform_action(document, user_id, bulk_action)
    msg = "#{bulk_action}: #{document.name}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase
    when "send commitment agreement"
      if document.approved && %w[InvestorKyc CapitalCommitment].include?(document.owner_type)

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
end
