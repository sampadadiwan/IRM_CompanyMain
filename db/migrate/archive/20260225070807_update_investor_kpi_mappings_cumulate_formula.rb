class UpdateInvestorKpiMappingsCumulateFormula < ActiveRecord::Migration[8.1]
  def up
    if column_exists?(:investor_kpi_mappings, :cumulate_formula)
      # rename cumulate formula to compute formula for clarity
      rename_column :investor_kpi_mappings, :cumulate_formula, :compute_formula
    end
    if column_exists?(:investor_kpi_mappings, :cumulate)
      # rename cumulate to autofill
      rename_column :investor_kpi_mappings, :cumulate, :autofill
    end
    if column_exists?(:kpi_reports, :cumulation_completed)
      rename_column :kpi_reports, :cumulation_completed, :autofill_completed
    end
  end

  def down
    if column_exists?(:investor_kpi_mappings, :compute_formula)
      rename_column :investor_kpi_mappings, :compute_formula, :cumulate_formula
    end
    if column_exists?(:investor_kpi_mappings, :autofill)
      rename_column :investor_kpi_mappings, :autofill, :cumulate
    end
    if column_exists?(:kpi_reports, :autofill_completed)
      rename_column :kpi_reports, :autofill_completed, :cumulation_completed
    end
  end
end
