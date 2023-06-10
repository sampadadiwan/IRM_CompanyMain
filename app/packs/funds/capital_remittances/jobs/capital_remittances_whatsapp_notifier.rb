class CapitalRemittancesWhatsappNotifier < WhatsappNotifier
  def perform(user, crid)
    if user.blank?
      Rails.logger.error "Error: User required to send Capital Remittance Whatsapp Notification"
      return
    elsif user.present? && (!user.whatsapp_enabled || user.phone.blank?)
      Rails.logger.error "Error: Whatsapp Not Enabled or Invalid Number for User ID #{user.id}"
      return
    end
    self.class.send_notification(user, crid)
  end

  def self.send_notification(user, crid)
    whnos = ApplicationMailer.new.sandbox_whatsapp_numbers(user, [user.phone_with_call_code])
    whnos.each do |whatsapp_no|
      capital_remittance = CapitalRemittance.find(crid)

      broadcast_name = "capital call noti broadcast"
      template_name = ENV.fetch('CAPITAL_REMITTANCE_NOTI_TEMPLATE')
      investor_name = capital_remittance.investor_name
      fund_name = capital_remittance.fund.name
      entity_name = capital_remittance.entity.name
      capital_call_notes = "Capital Call Notes- #{capital_remittance.capital_call.notes}"
      capital_call_name = capital_remittance.capital_call.name
      capital_call_due_date = capital_remittance.capital_call.due_date.strftime("%d/%m/%Y")
      folio_id = capital_remittance.folio_id.to_s
      folio_call_amount = capital_remittance.folio_call_amount.to_s
      units_quantity = capital_remittance.units_quantity.to_s
      notes = (capital_remittance.notes.to_s.presence || " ")
      notes_name = notes.present? ? "Notes" : " "
      full_name = capital_remittance.investor_kyc&.full_name || " "
      full_name_field = full_name.present? ? "Full Name" : " "
      id = capital_remittance.id.to_s

      url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")

      http = get_http url
      request = get_post_request url
      request["content-type"] = 'text/json'
      request.body = "{\"parameters\":[{\"name\":\"header_investor_name\",\"value\":\"#{investor_name}\"},{\"name\":\"investor_name\",\"value\":\"#{investor_name}\"},{\"name\":\"fund_name\",\"value\":\"#{fund_name}\"},{\"name\":\"capital_call_notes\",\"value\":\"#{capital_call_notes}\"},{\"name\":\"capital_call_name\",\"value\":\"#{capital_call_name}\"},{\"name\":\"capital_call_due_date\",\"value\":\"#{capital_call_due_date}\"},{\"name\":\"folio_id\",\"value\":\"#{folio_id}\"},{\"name\":\"folio_call_amount\",\"value\":\"#{folio_call_amount}\"},{\"name\":\"units_quantity\",\"value\":\"#{units_quantity}\"},{\"name\":\"notes_name\",\"value\":\"#{notes_name}\"},{\"name\":\"notes\",\"value\":\"#{notes}\"},{\"name\":\"full_name_field\",\"value\":\"#{full_name_field}\"},{\"name\":\"full_name\",\"value\":\"#{full_name}\"},{\"name\":\"id\",\"value\":\"#{id}\"},{\"name\":\"entity_name\",\"value\":\"#{entity_name}\"}],\"broadcast_name\":\"#{broadcast_name}\",\"template_name\":\"#{template_name}\"}"

      response = http.request(request)
      response.read_body
    end
  end
end
