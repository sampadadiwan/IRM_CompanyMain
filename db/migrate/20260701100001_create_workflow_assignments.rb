class CreateWorkflowAssignments < ActiveRecord::Migration[7.1]
  def up
    create_table :workflow_assignments do |t|
      t.string  :workflowable_type,    null: false
      t.bigint  :workflowable_id,      null: false
      t.bigint  :workflow_template_id, null: false
      t.bigint  :created_by_id
      t.timestamps
    end

    add_index :workflow_assignments, [:workflowable_type, :workflowable_id],
              unique: true, name: "index_workflow_assignments_on_workflowable"
    add_index :workflow_assignments, :workflow_template_id,
              name: "index_workflow_assignments_on_workflow_template_id"

    # Backfill one assignment per folder that already had a template assigned
    execute <<~SQL
      INSERT INTO workflow_assignments
        (workflowable_type, workflowable_id, workflow_template_id, created_at, updated_at)
      SELECT 'Folder', id, workflow_template_id, NOW(), NOW()
      FROM folders
      WHERE workflow_template_id IS NOT NULL
    SQL
  end

  def down
    drop_table :workflow_assignments
  end
end
