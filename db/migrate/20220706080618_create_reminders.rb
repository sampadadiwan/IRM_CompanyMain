class CreateReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :reminders do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: false
      t.string :unit, limit: 10
      t.integer :count
      t.boolean :sent, default: false

      t.timestamps
    end
  end
end
