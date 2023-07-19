class CreateKpis < ActiveRecord::Migration[7.0]
  def change
    create_table :kpis do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.string :name, limit: 50
      t.decimal :value
      t.string :display_value, limit: 30
      t.string :notes
      t.text :properties
      t.references :kpi_report, null: false, foreign_key: true

      t.timestamps
    end
  end
end
