class AddDocumentIdsToAgentChart < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_charts, :document_ids, :string
  end
end
