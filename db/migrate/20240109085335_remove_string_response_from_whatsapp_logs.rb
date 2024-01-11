class RemoveStringResponseFromWhatsappLogs < ActiveRecord::Migration[7.1]
  def change
    WhatsappLog.all.each do |whatsapp_log|
      whatsapp_log.update(response: nil) if whatsapp_log.response&.starts_with?("WhatsApp not enabled for")
    end
  end
end
