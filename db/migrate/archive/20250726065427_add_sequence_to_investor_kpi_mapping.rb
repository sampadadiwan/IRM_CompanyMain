class AddSequenceToInvestorKpiMapping < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :position, :integer, default: 0
    add_column :investor_kpi_mappings, "ancestry", :string, collation: 'utf8mb4_bin'
    add_index :investor_kpi_mappings, "ancestry"

    InvestorKpiMapping.all.group_by(&:investor_id).each do |investor_id, mapping|
      mapping.each_with_index do |investor_kpi_mapping, index|
        investor_kpi_mapping.position = index
        investor_kpi_mapping.save
      end
    end
  end
end
