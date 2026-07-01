class RemoveWorkflowTemplateFkFromFolders < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :folders, :workflow_templates if foreign_key_exists?(:folders, :workflow_templates)
    remove_index  :folders, name: "index_folders_on_workflow_template_id", if_exists: true
    remove_column :folders, :workflow_template_id if column_exists?(:folders, :workflow_template_id)
  end

  def down
    add_column :folders, :workflow_template_id, :bigint unless column_exists?(:folders, :workflow_template_id)
    add_index  :folders, :workflow_template_id, name: "index_folders_on_workflow_template_id", if_not_exists: true
    add_foreign_key :folders, :workflow_templates unless foreign_key_exists?(:folders, :workflow_templates)
  end
end
