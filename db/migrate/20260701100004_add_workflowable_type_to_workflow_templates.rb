class AddWorkflowableTypeToWorkflowTemplates < ActiveRecord::Migration[7.1]
  def up
    # nullable so existing templates remain usable without forcing immediate type selection
    add_column :workflow_templates, :workflowable_type, :string unless column_exists?(:workflow_templates, :workflowable_type)

    # Backfill from existing WorkflowAssignment records where the type is unambiguous.
    # Templates with no assignments are left NULL (treated as unscoped until admin sets type).
    execute <<~SQL
      UPDATE workflow_templates wt
      INNER JOIN workflow_assignments wa ON wa.workflow_template_id = wt.id
      SET wt.workflowable_type = wa.workflowable_type
      WHERE wt.workflowable_type IS NULL
    SQL
  end

  def down
    remove_column :workflow_templates, :workflowable_type if column_exists?(:workflow_templates, :workflowable_type)
  end
end
