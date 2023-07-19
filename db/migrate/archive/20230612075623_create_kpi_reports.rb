class CreateKpiReports < ActiveRecord::Migration[7.0]
  def change
    create_table :kpi_reports do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.date :as_of
      t.text :notes
      t.text :properties
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
