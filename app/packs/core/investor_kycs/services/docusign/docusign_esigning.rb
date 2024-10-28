class DocusignEsigning < Trailblazer::Operation
  step :send_document_for_esign
  left :handle_errors, Output(:failure) => End(:failure)
  step :update_document

  def send_document_for_esign(ctx, helper:, doc:, **)
    ctx[:response] = helper.send_document_for_esign(doc)
    true
  rescue StandardError => e
    ctx[:error] = e
    false
  end

  def update_document(ctx, helper:, doc:, user_id:, **)
    helper.update_document(ctx[:response], doc)
    if user_id.present?
      UserAlert.new(user_id:, message: "Document - #{doc.name} eSign status updated ", level: "
      ").broadcast
    end
  end

  def handle_errors(ctx, **)
    handle_api_error if ctx[:error].is_a?(DocuSign_eSign::ApiError)
    ctx[:errors] = [ctx[:errors].to_s, ctx[:error]&.full_message].join(', ')
    false
  end

  def handle_api_error(ctx, **)
    error = JSON.parse ctx[:error].response_body
    @error_code = ctx[:error].code || error['errorCode']
    @error_message = error['error_description'] || error['message']

    Rails.logger.error "Error: #{@error_code} - #{@error_message}"
  end
end
