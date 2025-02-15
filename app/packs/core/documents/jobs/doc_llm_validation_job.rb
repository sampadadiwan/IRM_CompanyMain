class DocLlmValidationJob < ApplicationJob
  def perform(model_class, model_id, user_id, document_ids: nil)
    model = model_class.constantize.find(model_id)
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
      end
    end
  end
end
