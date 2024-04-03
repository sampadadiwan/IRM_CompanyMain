class CreateSupportClientMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :support_client_mappings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.date :end_date
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :support_client_mappings, :deleted_at
  end
end
