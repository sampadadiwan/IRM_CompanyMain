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
    UserAlert.new(user_id:, message: "Document - #{doc.name} eSign status updated ", level: "info").broadcast if user_id.present?
  end

  def handle_errors(ctx, doc:, user_id:, **)
    msg = "eSign failed for Document #{doc.id} - #{doc.name}"
    api_msg = handle_api_error(ctx) if ctx[:error].is_a?(DocuSign_eSign::ApiError)
    msg += if api_msg.present?
             "<br>#{api_msg}"
           else
             "<br>#{ctx[:error].message}"
           end
    ctx[:error_message] = msg
    Rails.logger.error msg
    UserAlert.new(user_id:, message: msg, level: "danger").broadcast if user_id.present?
    false
  end

  def handle_api_error(ctx, **)
    error = JSON.parse(ctx[:error].response_body)
    ctx[:error_code]    = ctx[:error].code || error['errorCode']
    ctx[:error_message] = error['error_description'] || error['message']

    "Error - Code: #{ctx[:error_code]}, Message: #{ctx[:error_message]}"
  end
end
