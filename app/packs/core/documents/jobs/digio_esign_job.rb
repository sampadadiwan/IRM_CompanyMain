# Purpose: To send a document for e-signing to Digio
class DigioEsignJob < ApplicationJob
  def perform(document_id)
    Chewy.strategy(:sidekiq) do
      doc = Document.find(document_id)
      response = DigioEsignHelper.new.sign(doc)

      if response.success?
        doc.update(sent_for_esign: true, provider_doc_id: JSON.parse(response.body)["id"])
      else
        e = StandardError.new("Error sending #{doc.name} for e-signing - #{JSON.parse(response.body)}")
        ExceptionNotifier.notify_exception(e)
        logger.error e.message
        doc.update(sent_for_esign: true, esign_status: "failed", provider_doc_id: JSON.parse(response.body)["id"])

        doc.e_signatures.each do |esign|
          esign.add_api_update(JSON.parse(response.body))
          esign.update(status: "failed", api_updates: esign.api_updates)
        end
        # raise e # uncomment to raise error
      end
    end
  end
end
