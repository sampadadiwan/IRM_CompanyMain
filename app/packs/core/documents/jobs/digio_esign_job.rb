# Purpose: To send a document for e-signing to Digio
class DigioEsignJob < ApplicationJob
  def perform(document_id, user_id = nil, folder_id: nil)
    Chewy.strategy(:active_job) do
      if folder_id.present?
        send_documents_for_esign(folder_id, user_id)
      else
        doc = Document.find(document_id)
        process_document(doc, user_id)
      end
    end
  end

  def process_document(doc, user_id = nil)
    response = DigioEsignHelper.new.sign(doc)

    json_res = JSON.parse(response.body)
    if response.success?
      doc.update(sent_for_esign: true, sent_for_esign_date: Time.zone.now, provider_doc_id: json_res["id"], esign_status: "requested")
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
  rescue JSON::ParserError => e
    # 502 bad gateway response cannot be parsed
    msg = "Error sending #{doc.name} for e-signing - #{e.message}"
    ExceptionNotifier.notify_exception(StandardError.new(msg))
    logger.error msg
    send_notification(msg, user_id, :danger)
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
      DigioEsignJob.set(wait: rand(documents.count * 15).seconds).perform_later(doc.id, user_id)
    end

    send_notification("Completed. #{documents.count} documents enqueued for eSigning", user_id, :info)
  end
end
