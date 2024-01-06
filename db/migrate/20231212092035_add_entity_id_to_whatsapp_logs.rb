class AddEntityIdToWhatsappLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_logs, :entity_id, :integer
    WhatsappLog.all.each do |whatsapp_log|
      whatsapp_log.update(entity_id: whatsapp_log.notification.entity_id)
    end
  end
end
