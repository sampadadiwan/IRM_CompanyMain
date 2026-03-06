class AddRecurrenceToTasks < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:tasks, :task_recurrence_rule_id)
      add_reference :tasks, :task_recurrence_rule, null: true, foreign_key: true
    end
    add_column :tasks, :original_start_date, :datetime unless column_exists?(:tasks, :original_start_date)
    add_column :tasks, :is_exception, :boolean, default: false unless column_exists?(:tasks, :is_exception)
  end
end
