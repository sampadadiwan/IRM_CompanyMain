# Purpose: To send a document for e-signing to Digio
class DigioEsignJob < ApplicationJob
  def perform(document_id, user_id = nil, folder_id: nil)
    send_notification("Started documents enqueuing for eSigning", user_id, :info)

    Chewy.strategy(:sidekiq) do
      documents = if folder_id.present?
                    documents_to_esign(document_id, folder_id)
                  else
                    Document.where(id: document_id)
                  end

      documents.each do |doc|
        process_document(doc, user_id)
      end

      send_notification("Completed. #{documents.count} documents enqueued for eSigning", user_id, :info)
    end
  end

  def process_document(doc, user_id = nil)
    response = DigioEsignHelper.new.sign(doc)

    json_res = JSON.parse(response.body)
    if response.success?
      doc.update(sent_for_esign: true, provider_doc_id: json_res["id"], esign_status: "requested")
      EsignUpdateJob.perform_later(doc.id, user_id) unless Document::SKIP_ESIGN_UPDATE_STATUSES.include?(doc.esign_status)
    else
      doc.update(sent_for_esign: true, esign_status: "failed", provider_doc_id: json_res["id"])

      doc.e_signatures.each do |esign|
        esign.add_api_update(json_res)
        esign.update(status: "failed", api_updates: esign.api_updates)
      end

      msg = "Error sending #{doc.name} for e-signing - #{json_res['message']}"
      ExceptionNotifier.notify_exception(StandardError.new(msg))
      logger.error msg
      send_notification(msg, user_id, :danger)
    end
  end

  def documents_to_esign(entity_id, folder_id)
    if folder_id.present?
      # Get all the documents in the folder and its subfolders
      parent_folder = Folder.find(folder_id)
      folder_ids = parent_folder.descendant_ids << folder_id
      documents = Document.where(folder_id: folder_ids)
    else
      # Get all the documents in the entity
      documents = Document.where(entity_id:)
    end

    # Get all the generated documents
    documents = documents.not_template.not_sent_for_esign.generated
    # Dont include the Cancelled or completed ones
    documents = documents.where.not(esign_status: Document::SKIP_ESIGN_UPDATE_STATUSES)

    Rails.logger.debug { "Found #{documents.count} documents to esign" }
    documents
  end
end
