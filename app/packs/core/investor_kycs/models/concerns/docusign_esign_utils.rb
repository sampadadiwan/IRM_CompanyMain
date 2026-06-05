module DocusignEsignUtils
  extend ActiveSupport::Concern

  def get_envelope(envelope_api, doc)
    envelope_api.get_envelope(args(doc.entity_id)[:account_id], doc.provider_doc_id)
  end

  def get_recipients(envelope_api, doc)
    envelope_api.list_recipients(args(doc.entity_id)[:account_id], doc.provider_doc_id)
  end

  def handle_error(err)
    error = JSON.parse err.response_body
    @error_code = err.code || error['errorCode']
    @error_message = error['error_description'] || error['message']

    msg = "Error - Code: #{@error_code}, Message: #{@error_message}"
    Rails.logger.error msg
    msg
  end
end
