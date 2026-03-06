class ChangeCumulateToStringInInvestorKpiMappings < ActiveRecord::Migration[7.1]
  def up
    # Create a temporary column
    add_column :investor_kpi_mappings, :cumulate_string, :string

    # Migrate data
    InvestorKpiMapping.reset_column_information
    InvestorKpiMapping.all.each do |mapping|
      mapping.update_column(:cumulate_string, mapping.cumulate ? 'cumulate' : nil)
    end

    # Remove old column and rename new one
    remove_column :investor_kpi_mappings, :cumulate
    rename_column :investor_kpi_mappings, :cumulate_string, :cumulate
  end

  def down
    # Reverse the process
    add_column :investor_kpi_mappings, :cumulate_boolean, :boolean

    InvestorKpiMapping.reset_column_information
    InvestorKpiMapping.all.each do |mapping|
      mapping.update_column(:cumulate_boolean, mapping.cumulate == 'cumulate')
    end

    remove_column :investor_kpi_mappings, :cumulate
    rename_column :investor_kpi_mappings, :cumulate_boolean, :cumulate
  end
end
