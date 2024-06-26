class DropUnwantedTables < ActiveRecord::Migration[7.1]
  def up
    drop_table :solid_queue_pauses
    drop_table :solid_queue_processes
    drop_table :solid_queue_semaphores
    drop_table :solid_queue_scheduled_executions
    drop_table :solid_queue_ready_executions
    drop_table :solid_queue_claimed_executions
    drop_table :solid_queue_blocked_executions
    drop_table :solid_queue_failed_executions
    drop_table :solid_queue_recurring_executions
    drop_table :solid_queue_jobs
    drop_table :abraham_histories
    drop_table :impressions
  end

  def down
  end
end
