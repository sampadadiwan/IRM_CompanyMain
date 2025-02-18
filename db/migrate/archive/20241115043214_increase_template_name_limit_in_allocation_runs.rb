class IncreaseTemplateNameLimitInAllocationRuns < ActiveRecord::Migration[7.1]
  def change
    change_column :allocation_runs, :template_name, :string, limit: 50
  end
end
