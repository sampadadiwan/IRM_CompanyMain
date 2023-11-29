# Approved generated documents once they are reviewed, so investors can view them
class DocumentApprovalJob < ApplicationJob
  queue_as :low

  # parent_folder_id is the root folder_id that contains the generated documents
  # start_date and end_date are the date range to search for generated documents
  # options : user_id: nil, notification: false, owner_type: nil, parent_folder_id: nil
  def perform(entity_id, start_date, end_date, options)
    parent_folder_id = options[:parent_folder_id]
    user_id = options[:user_id]
    notification = options[:notification]
    owner_type = options[:owner_type]

    send_notification("Document approval #{start_date} - #{end_date} started", user_id, "info")

    Chewy.strategy(:sidekiq) do
      if parent_folder_id.present?
        # Get all the documents in the folder and its subfolders
        parent_folder = Folder.find(parent_folder_id)
        folder_ids = parent_folder.descendant_ids << parent_folder_id
        documents = Document.where(folder_id: folder_ids)
      else
        # Get all the documents in the entity
        documents = Document.where(entity_id:)
      end

      # Get all the generated documents in the date range
      documents = documents.generated.where(created_at: start_date..end_date.end_of_day)
      # Get all the generated documents with owner_type like InvestorKYC, CapitalCommitment, etc.
      documents = documents.where(owner_type:) if owner_type.present?

      Rails.logger.debug { "Found #{documents.count} documents to approve" }

      documents.find_each do |document|
        Rails.logger.debug { "Approving document #{document.name}, #{document.id}" }
        # Approve the document
        document.approved = true
        document.approved_by_id = user_id
        # Send notification to the document owner
        document.send_email = true if notification
        document.save

        document.send_notification_for_owner if notification
      rescue StandardError => e
        Rails.logger.error("Document approval for #{doc.name}, #{doc.id} failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        send_notification("Document approval for #{doc.name}, #{doc.id} failed: #{e.message}", user_id, "danger")
      end
    end

    send_notification("Document approval completed", user_id, "info")
  end
end
