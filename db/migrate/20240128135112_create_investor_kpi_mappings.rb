class CreateInvestorKpiMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :investor_kpi_mappings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.string :reported_kpi_name, limit: 50
      t.string :standard_kpi_name, limit: 50
      t.decimal :lower_threshold, precision: 20, scale: 2, default: 0
      t.decimal :upper_threshold, precision: 20, scale: 2, default: 0

      t.timestamps
    end
    add_index :investor_kpi_mappings, :reported_kpi_name
    add_index :investor_kpi_mappings, :standard_kpi_name
  end
end
