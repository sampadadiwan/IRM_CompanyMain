class CreateCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :custom_notifications do |t|
      t.string :subject
      t.text :body
      t.string :whatsapp
      t.references :entity, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: false

      t.timestamps
    end
  end
end
