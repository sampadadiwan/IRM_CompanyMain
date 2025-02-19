class AddEsignLogs < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:esign_logs)
      create_table :esign_logs do |t|
        t.references :document, null: true, foreign_key: true
        t.references :entity, null: false, foreign_key: true
        t.json :request_data
        t.json :response_data
        t.json :webhook_data
        t.json :manual_update_data
        t.timestamps
      end
    end
  end
end
