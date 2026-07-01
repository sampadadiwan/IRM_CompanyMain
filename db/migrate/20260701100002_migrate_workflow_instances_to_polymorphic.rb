class MigrateWorkflowInstancesToPolymorphic < ActiveRecord::Migration[7.1]
  def up
    # Guard each add_column — MySQL's non-transactional DDL can leave columns behind on a failed run
    add_column :workflow_instances, :workflowable_type,     :string  unless column_exists?(:workflow_instances, :workflowable_type)
    add_column :workflow_instances, :workflowable_id,       :bigint  unless column_exists?(:workflow_instances, :workflowable_id)
    add_column :workflow_instances, :workflow_assignment_id, :bigint unless column_exists?(:workflow_instances, :workflow_assignment_id)
    add_column :workflow_instances, :entity_id,             :bigint  unless column_exists?(:workflow_instances, :entity_id)

    execute <<~SQL
      UPDATE workflow_instances wi
      INNER JOIN folders f ON f.id = wi.folder_id
      LEFT JOIN workflow_assignments wa
        ON wa.workflowable_type = 'Folder' AND wa.workflowable_id = wi.folder_id
      SET wi.workflowable_type      = 'Folder',
          wi.workflowable_id        = wi.folder_id,
          wi.workflow_assignment_id = wa.id,
          wi.entity_id              = f.entity_id
    SQL

    change_column_null :workflow_instances, :workflowable_type, false
    change_column_null :workflow_instances, :workflowable_id,   false
    change_column_null :workflow_instances, :entity_id,         false
    # workflow_assignment_id stays nullable — instances whose assignment was later deleted remain readable

    add_index :workflow_instances, [:workflowable_type, :workflowable_id, :status],
              name: "index_workflow_instances_on_workflowable_and_status",
              if_not_exists: true
    add_index :workflow_instances, :workflow_assignment_id,
              name: "index_workflow_instances_on_workflow_assignment_id",
              if_not_exists: true
    add_index :workflow_instances, :entity_id,
              name: "index_workflow_instances_on_entity_id",
              if_not_exists: true

    # Must drop the FK before dropping the index and column
    if foreign_key_exists?(:workflow_instances, :folders)
      remove_foreign_key :workflow_instances, :folders
    end
    remove_index  :workflow_instances, name: "index_workflow_instances_on_folder_and_status", if_exists: true
    remove_index  :workflow_instances, name: "index_workflow_instances_on_folder_id",          if_exists: true
    remove_column :workflow_instances, :folder_id if column_exists?(:workflow_instances, :folder_id)
  end

  def down
    add_column :workflow_instances, :folder_id, :bigint unless column_exists?(:workflow_instances, :folder_id)

    execute <<~SQL
      UPDATE workflow_instances
      SET folder_id = workflowable_id
      WHERE workflowable_type = 'Folder'
    SQL

    change_column_null :workflow_instances, :folder_id, false
    add_index :workflow_instances, [:folder_id, :status],
              name: "index_workflow_instances_on_folder_and_status", if_not_exists: true
    add_index :workflow_instances, :folder_id,
              name: "index_workflow_instances_on_folder_id", if_not_exists: true
    add_foreign_key :workflow_instances, :folders unless foreign_key_exists?(:workflow_instances, :folders)

    remove_index  :workflow_instances, name: "index_workflow_instances_on_workflowable_and_status", if_exists: true
    remove_index  :workflow_instances, name: "index_workflow_instances_on_workflow_assignment_id",   if_exists: true
    remove_index  :workflow_instances, name: "index_workflow_instances_on_entity_id",                if_exists: true
    remove_column :workflow_instances, :workflowable_type     if column_exists?(:workflow_instances, :workflowable_type)
    remove_column :workflow_instances, :workflowable_id       if column_exists?(:workflow_instances, :workflowable_id)
    remove_column :workflow_instances, :workflow_assignment_id if column_exists?(:workflow_instances, :workflow_assignment_id)
    remove_column :workflow_instances, :entity_id             if column_exists?(:workflow_instances, :entity_id)
  end
end
