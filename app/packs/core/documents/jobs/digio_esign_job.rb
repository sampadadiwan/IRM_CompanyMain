# Purpose: To send a document for e-signing to Digio
class DigioEsignJob < ApplicationJob
  def perform(document_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      doc = Document.find(document_id)
      response = DigioEsignHelper.new.sign(doc)

      json_res = JSON.parse(response.body)
      if response.success?
        doc.update(sent_for_esign: true, provider_doc_id: json_res["id"], esign_status: "requested")
      else
        e = StandardError.new("Error sending #{doc.name} for e-signing - #{json_res}")
        ExceptionNotifier.notify_exception(e)
        logger.error e.message
        doc.update(sent_for_esign: true, esign_status: "failed", provider_doc_id: json_res["id"])

        doc.e_signatures.each do |esign|
          esign.add_api_update(json_res)
          esign.update(status: "failed", api_updates: esign.api_updates)
        end
        UserAlert.new(user_id:, message: "Error sending #{doc.name} for e-signing - #{json_res['message']}", level: "failure").broadcast if user_id.present? && (json_res['code'] == "NOT_SUFFICIENT_STAMPS")
        logger.error e.message
        # raise e # uncomment to raise error
      end
    end
  end
end
