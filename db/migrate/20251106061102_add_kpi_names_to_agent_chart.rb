class AddKpiNamesToAgentChart < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_charts, :kpi_names, :string
    add_column :agent_charts, :tag_list, :string
    rename_column :agent_charts, :document_ids, :document_names
  end
end
