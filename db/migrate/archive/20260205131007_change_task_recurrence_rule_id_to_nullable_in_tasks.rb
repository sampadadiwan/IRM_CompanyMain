class ChangeTaskRecurrenceRuleIdToNullableInTasks < ActiveRecord::Migration[8.1]
  def change
    change_column_null :tasks, :task_recurrence_rule_id, true
  end
end
