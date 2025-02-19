# Purpose: To send a document for e-signing to Digio
class EsignJob < ApplicationJob
  def perform(document_id, user_id = nil, folder_id: nil)
    Chewy.strategy(:sidekiq) do
      if folder_id.present?
        send_documents_for_esign(folder_id, user_id)
      else
        doc = Document.find(document_id)
        process_document(doc, user_id)
      end
    end
  end

  def process_document(doc, user_id = nil)
    result = EsignHelper.new(doc, user_id:).sign
    if result[0]
      send_notification("Document - #{doc.name} sent for eSigning", user_id, :info)
    else
      send_notification(result[1].to_s, user_id, :danger)
    end
  end

  def send_documents_for_esign(folder_id, user_id)
    parent_folder = Folder.find(folder_id)
    folder_ids = parent_folder.descendant_ids << folder_id
    documents = Document.where(folder_id: folder_ids)

    # Get all the generated documents
    documents = documents.not_template.not_sent_for_esign.generated.approved
    # Dont include the Cancelled or completed ones
    documents = documents.where.not(esign_status: Document::SKIP_ESIGN_UPDATE_STATUSES)

    Rails.logger.debug { "Found #{documents.count} documents to esign" }
    documents.each do |doc|
      # Schedule each doc for esigning
      EsignJob.set(wait: rand(documents.count * 15).seconds).perform_later(doc.id, user_id)
    end

    if documents.blank?
      send_notification("No documents found for eSigning", user_id, :warning)
    else
      send_notification("Completed. #{documents.count} documents enqueued for eSigning", user_id, :info)
    end
  end
end
