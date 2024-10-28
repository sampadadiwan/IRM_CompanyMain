class DigioEsigning < Trailblazer::Operation
  step :send_document_for_esign
  step :update_document

  def send_document_for_esign(ctx, helper:, doc:, **)
    ctx[:response] = helper.send_document_for_esign(doc)
  end

  def update_document(ctx, helper:, doc:, user_id:, **)
    helper.update_document(ctx[:response], doc, user_id)
  end
end
