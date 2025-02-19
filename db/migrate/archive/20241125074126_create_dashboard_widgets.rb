class CreateDashboardWidgets < ActiveRecord::Migration[7.2]
  def change
    create_table :dashboard_widgets do |t|
      t.string :dashboard_name, limit: 30
      t.references :entity, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: true
      t.string :widget_name, limit: 30
      t.string :tags, limit: 100
      t.integer :position
      t.text :metadata
      t.string :size, limit: 10
      t.boolean :enabled

      t.timestamps
    end
  end
end
