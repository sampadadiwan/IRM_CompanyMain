module WithDocQuestions
  extend ActiveSupport::Concern

  included do
    # serialize :doc_question_answers, JSON
    attribute :doc_question_answers, :json, default: {}
  end

  def validate_document(document)
    DocLlmValidator.call(model: self, document:)
  end

  def validate_all_documents
    # We can validate only those documents which have doc_questions
    documents.where(name: document_names_for_validation).find_each do |document|
      validate_document(document)
    end
  end

  # We can validate only those documents which have doc_questions
  def document_names_for_validation
    entity.doc_questions.pluck(:document_name).uniq
  end

  # Get all the questions for this model and document
  def doc_questions_for(document)
    doc_questions.where(document_name: document.name)
  end

  # GEt all the questions for this model
  def doc_questions
    entity.doc_questions.where(owner: entity, for_class: self.class.name)
  end

  # This method is called by the DocLlmValidator service
  # Override this method in the class where this concern is included, to mark the specific model as validated if required
  def mark_as_validated(all_docs_valid)
    Rails.logger.debug { "#{self}: All docs valid: #{all_docs_valid}" }
    self.all_docs_valid = all_docs_valid if respond_to?(:all_docs_valid)
    save(validate: false)
  end
end
