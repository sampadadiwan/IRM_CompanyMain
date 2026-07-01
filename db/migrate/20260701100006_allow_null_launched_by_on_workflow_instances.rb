class AllowNullLaunchedByOnWorkflowInstances < ActiveRecord::Migration[7.1]
  # Auto-assignment rules launch instances without an interactive user (system-initiated).
  # Allow launched_by_id to be NULL so auto-launch works without a user context.
  def up
    change_column_null :workflow_instances, :launched_by_id, true
  end

  def down
    change_column_null :workflow_instances, :launched_by_id, false
  end
end
