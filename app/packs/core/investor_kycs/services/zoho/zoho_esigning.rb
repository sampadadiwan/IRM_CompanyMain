class ZohoEsigning < Trailblazer::Operation
  step :check_account
  step :validate_signer_count
  step :validate_doc_size
  step :send_document_for_esign
  step :update_document
  left :log_errors

  # X11: the company's own account is the one to send on, and Zoho has rejected its credentials.
  def check_account(ctx, doc:, **)
    return true unless ZohoSignAccount.for_entity(doc.entity).connection&.needs_reauth?

    ctx[:errors] = "#{doc.entity.name}'s Zoho account needs to be reconnected. Ask a company admin to reconnect it on the company page."
    false
  end

  # E17 (25 signers sent), X12 (26 refused before anything reaches Zoho)
  def validate_signer_count(ctx, doc:, **)
    return true if doc.e_signatures.count <= ZohoEsignHelper::MAX_SIGNERS

    ctx[:errors] = "Zoho allows at most #{ZohoEsignHelper::MAX_SIGNERS} signers per document."
    false
  end

  def validate_doc_size(ctx, helper:, doc:, **)
    validation_result = helper.validate_doc_size(doc, ctx[:user_id])
    ctx[:errors] = validation_result.errors unless validation_result.success?
    validation_result.success?
  end

  # X13 (Zoho unreachable / timed out), X14 (unreadable PDF), X15 (submit refused after create):
  # every send failure becomes a Failed document the user can resend - sends are never retried
  # automatically, so a half-done send can't create a second request.
  def send_document_for_esign(ctx, helper:, doc:, **)
    ctx[:response] = helper.send_document_for_esign(doc)
  rescue ZohoSignClient::Error, PDF::Reader::MalformedPDFError => e
    ctx[:errors] = helper.send_failed(doc, e).errors
    false
  end

  def update_document(ctx, helper:, doc:, user_id:, **)
    result = helper.update_document(ctx[:response], doc, user_id)
    ctx[:message] = result.message
    ctx[:errors] = result.errors unless result.success?
    result.success?
  end

  def log_errors(ctx, **)
    Rails.logger.error(ctx[:errors]) if ctx[:errors].present?
    false
  end
end
