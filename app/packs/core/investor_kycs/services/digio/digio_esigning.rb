class DigioEsigning < Trailblazer::Operation
  step :validate_doc_size
  left :handle_doc_size_error, Output(:failure) => End(:failure)
  step :send_document_for_esign
  step :update_document
  left :handle_esign_errors, Output(:failure) => End(:failure)

  def validate_doc_size(ctx, helper:, doc:, **)
    validation_result = helper.validate_doc_size(doc, ctx[:user_id])
    ctx[:validation_result] = validation_result
    validation_result.success
  end

  def handle_doc_size_error(ctx, **)
    validation_result = ctx[:validation_result]
    if validation_result.errors.present?
      Rails.logger.error(validation_result.errors)
      ctx[:errors] = validation_result.errors
      return false
    end
    false
  end

  def send_document_for_esign(ctx, helper:, doc:, **)
    ctx[:response] = helper.send_document_for_esign(doc)
  end

  def update_document(ctx, helper:, doc:, user_id:, **)
    ctx[:update_doc_result] = helper.update_document(ctx[:response], doc, user_id)
    ctx[:update_doc_result].success?
  end

  def handle_esign_errors(ctx, **)
    ctx[:errors] = ctx[:update_doc_result].errors if ctx[:update_doc_result].errors.present?
    false
  end
end
