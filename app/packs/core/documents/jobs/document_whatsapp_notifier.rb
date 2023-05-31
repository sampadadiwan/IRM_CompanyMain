class DocumentWhatsappNotifier < WhatsappNotifier
  # call perform with params for sending whatsapp notification
  # params = {
  #   whatsapp_no: "91xxxxxxxxxx",
  #   entity_name: "entity_name",
  #   doc_name: "doc_name",
  #   doc_id: "doc_id"
  # }
  def perform(params)
    if params["whatsapp_nos"].present?
      self.class.send_multiple_notifications(params)
    else
      self.class.send_notification(params)
    end
  end

  def self.send_notification(params)
    whatsapp_no = params["whatsapp_no"]
    entity_name = params["entity_name"]
    doc_name = params["doc_name"]
    doc_id = params["doc_id"]
    if whatsapp_no.blank? || entity_name.blank? || doc_name.blank? || doc_id.blank?
      Rails.logger.error "Invalid params for Document Whatsapp Notifier#send_notification - #{params}"
      return
    end
    url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")
    http = get_http url
    request = get_post_request url
    request["content-type"] = 'text/json'
    request.body = "{\"parameters\":[{\"name\":\"entity_name\",\"value\":\"#{entity_name}\"},{\"name\":\"name\",\"value\":\"#{doc_name}\"},{\"name\":\"id\",\"value\":\"#{doc_id}\"}],\"broadcast_name\":\"new document broadcast\",\"template_name\":\"notify_new_document\"}"
    response = http.request(request)
    response.read_body
  end

  def self.send_multiple_notifications(params)
    entity_name = params["entity_name"]
    doc_name = params["doc_name"]
    doc_id = params["doc_id"]
    whatsapp_nos = params['whatsapp_nos']
    if entity_name.blank? || doc_name.blank? || doc_id.blank? || whatsapp_nos.blank?
      Rails.logger.error "Invalid params for Document Whatsapp Notifier#sendmultiplenotificaitons - #{params}"
      return
    end

    url = URI("#{Rails.application.credentials[:WHATSAPP_API_ENDPOINT]}/api/v1/sendTemplateMessages")
    http = get_http url
    request = get_post_request url
    request["content-type"] = 'text/json'
    strs = []
    whatsapp_nos.each do |whno|
      strs << "{\"customParams\":[{\"name\":\"entity_name\",\"value\":\"#{entity_name}\"},{\"name\":\"name\",\"value\":\"#{doc_name}\"},{\"name\":\"id\",\"value\":\"#{doc_id}\"}],\"whatsappNumber\":\"#{whno}}\"}"
    end
    request.body = "{\"receivers\":[#{strs.join(',')}],\"broadcast_name\":\"notify new document multiple broaddcast\",\"template_name\":\"notify_new_document\"}"
    response = http.request(request)
    response.read_body
  end
end
