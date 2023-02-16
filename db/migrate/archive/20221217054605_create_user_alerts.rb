class CreateUserAlerts < ActiveRecord::Migration[7.0]
  def change
    create_table :user_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :message
      t.references :entity, null: false, foreign_key: true
      t.string :level, limit: 8

      t.timestamps
    end
  end
end
