class AddImportUploadIdToAgentChart < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_charts, :import_upload_id, :integer, null: true
  end
end
