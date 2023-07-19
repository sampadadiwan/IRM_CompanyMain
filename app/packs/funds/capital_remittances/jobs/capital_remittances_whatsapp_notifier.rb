class CapitalRemittancesWhatsappNotifier < WhatsappNotifier
  def perform(user, crid, template)
    if user.blank?
      Rails.logger.error "Error: User required to send Capital Remittance Whatsapp Notification"
      return
    elsif user.present? && (!user.whatsapp_enabled || user.phone.blank?)
      Rails.logger.error "Error: Whatsapp Not Enabled or Invalid Number for User ID #{user.id}"
      return
    end

    case template.to_s
    when ENV.fetch("CAPITAL_REMITTANCE_NOTI_TEMPLATE")
      self.class.send_notification(user, crid, template)
    when ENV.fetch('CAPITAL_REMITTANCE_PAYMENT_TEMPLATE')
      self.class.payment_received_notification(user, crid, template)
    else
      Rails.logger.error "Error: Invalid template name (#{template})"
    end
  end

  def self.send_notification(user, crid, template)
    whnos = ApplicationMailer.new.sandbox_whatsapp_numbers(user, [user.phone_with_call_code])
    whnos.each do |whatsapp_no|
      capital_remittance = CapitalRemittance.find(crid)

      broadcast_name = "capital call noti broadcast"
      template_name = template
      id, investor_name, fund_name, entity_name, capital_call_name, capital_call_due_date, folio_id, folio_call_amount, units_quantity = capital_remittance_info(capital_remittance)
      capital_call_notes = "Capital Call Notes- #{capital_remittance.capital_call.notes}"
      notes = (capital_remittance.notes.to_s.presence || " ")
      notes_name = notes.present? ? "Notes" : " "
      full_name = capital_remittance.investor_kyc&.full_name || " "
      full_name_field = full_name.present? ? "Full Name" : " "

      url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")

      http = get_http url
      request = get_post_request url
      request["content-type"] = 'text/json'
      request.body = "{\"parameters\":[{\"name\":\"header_investor_name\",\"value\":\"#{investor_name}\"},{\"name\":\"investor_name\",\"value\":\"#{investor_name}\"},{\"name\":\"fund_name\",\"value\":\"#{fund_name}\"},{\"name\":\"capital_call_notes\",\"value\":\"#{capital_call_notes}\"},{\"name\":\"capital_call_name\",\"value\":\"#{capital_call_name}\"},{\"name\":\"capital_call_due_date\",\"value\":\"#{capital_call_due_date}\"},{\"name\":\"folio_id\",\"value\":\"#{folio_id}\"},{\"name\":\"folio_call_amount\",\"value\":\"#{folio_call_amount}\"},{\"name\":\"units_quantity\",\"value\":\"#{units_quantity}\"},{\"name\":\"notes_name\",\"value\":\"#{notes_name}\"},{\"name\":\"notes\",\"value\":\"#{notes}\"},{\"name\":\"full_name_field\",\"value\":\"#{full_name_field}\"},{\"name\":\"full_name\",\"value\":\"#{full_name}\"},{\"name\":\"id\",\"value\":\"#{id}\"},{\"name\":\"entity_name\",\"value\":\"#{entity_name}\"}],\"broadcast_name\":\"#{broadcast_name}\",\"template_name\":\"#{template_name}\"}"

      response = http.request(request)
      response.read_body
    end
  end

  def self.payment_received_notification(user, crid, template)
    whnos = ApplicationMailer.new.sandbox_whatsapp_numbers(user, [user.phone_with_call_code])
    capital_remittance = CapitalRemittance.find(crid)
    broadcast_name = "capital call payment received broadcast"
    template_name = template

    id, investor_name, fund_name, entity_name, capital_call_name, capital_call_due_date, folio_id, folio_call_amount, units_quantity = capital_remittance_info(capital_remittance)
    payment_date = ""
    payment_date = capital_remittance.payment_date.strftime("%d/%m/%Y") if capital_remittance.payment_date.present?
    folio_collected_amount = capital_remittance.folio_collected_amount.to_s

    whnos.each do |whatsapp_no|
      url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")

      http = get_http url
      request = get_post_request url
      request["content-type"] = 'text/json'
      request.body = "{\"parameters\":[{\"name\":\"investor_name\",\"value\":\"#{investor_name}\"},{\"name\":\"fund_name\",\"value\":\"#{fund_name}\"},{\"name\":\"capital_call_name\",\"value\":\"#{capital_call_name}\"},{\"name\":\"capital_call_due_date\",\"value\":\"#{capital_call_due_date}\"},{\"name\":\"folio_id\",\"value\":\"#{folio_id}\"},{\"name\":\"folio_call_amount\",\"value\":\"#{folio_call_amount}\"},{\"name\":\"units_quantity\",\"value\":\"#{units_quantity}\"},{\"name\":\"1\",\"value\":\"#{id}\"},{\"name\":\"entity_name\",\"value\":\"#{entity_name}\"},{\"name\":\"payment_amt\",\"value\":\"#{folio_collected_amount}\"},{\"name\":\"capital_call_payment_date\",\"value\":\"#{payment_date}\"},{\"name\":\"folio_collected_amount\",\"value\":\"#{folio_collected_amount}\"}],\"broadcast_name\":\"#{broadcast_name}\",\"template_name\":\"#{template_name}\"}"

      response = http.request(request)
      response.read_body
    end
  end

  def self.capital_remittance_info(capital_remittance)
    [capital_remittance.id,
     capital_remittance.investor_name,
     capital_remittance.fund.name,
     capital_remittance.entity.name,
     capital_remittance.capital_call.name,
     capital_remittance.capital_call.due_date.strftime("%d/%m/%Y"),
     capital_remittance.folio_id.to_s,
     capital_remittance.folio_call_amount.to_s,
     capital_remittance.units_quantity.to_s]
  end
end
