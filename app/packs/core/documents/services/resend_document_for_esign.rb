class ResendDocumentForEsign < Trailblazer::Operation
  step :reset_doc_esignature
  left :handle_errors, Output(:failure) => End(:failure)
  step :send_document_for_esign

  def reset_doc_esignature(_ctx, document:, **)
    result = document.update(sent_for_esign: false, esign_status: "")

    # A new request notifies its signers again (embedded eSigning), so the notified marker goes with the statuses
    document.e_signatures.update_all(status: "", signing_notified_at: nil) if result
    result
  end

  def handle_errors(ctx, document:, **)
    unless document.valid?
      ctx[:errors] = document.errors.full_messages.join(", ")
      Rails.logger.error("Document errors: #{document.errors.full_messages}")
    end
    document.valid?
  end

  def send_document_for_esign(_ctx, document:, user_id:, **)
    document.send_for_esign(user_id:)
  end
end
