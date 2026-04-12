class CreateKpiChartSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :kpi_chart_settings do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :portfolio_company, foreign_key: { to_table: :investors }
      t.json :config, null: false
      t.boolean :is_default, default: false

      t.timestamps
    end
  end
end
