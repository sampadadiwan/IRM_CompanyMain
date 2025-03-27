class DocLlmValidationJob < ApplicationJob
  def perform(model_class, model_id, user_id, document_ids: nil)
    model = model_class.constantize.find(model_id)
    @error_msgs = []
    Chewy.strategy(:sidekiq) do
      send_notification("Document validation started for #{model}. This will take time so please be patient..", user_id, "info")
      docs = if document_ids.present?
               # Specific documents
               model.documents.where(id: document_ids)
             else
               # All documents which have doc_questions
               model.documents.where(name: model.document_names_for_validation)
             end

      docs.each do |document|
        model.validate_document(document)
        model.reload
        send_notification("Document #{document.name} validation completed for #{model}", user_id, "success")
      end
      if docs.present?
        send_notification("Document validation completed for #{model}.", user_id, "success")
      else
        send_notification("No documents to validate for #{model}.", user_id, "danger")
        @error_msgs << { msg: "No documents to validate", id: model.id, model: model }
      end
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      send_notification("Error in validating documents for #{model}: #{e.message}", user_id, "danger")
      @error_msgs << { msg: e.message, id: model.id, model: model }
    end
    @error_msgs
  end
end
