class CreateWhatsappLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_logs do |t|
      t.references :notification, null: false, foreign_key: true
      t.json :params
      t.json :response
      t.json :entity_name
      t.boolean :name_matched

      t.timestamps
    end

  end
end
