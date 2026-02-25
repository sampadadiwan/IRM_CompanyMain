class AddPartialSuccessToExecutionLogStatusConstraint < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :agent_execution_logs, name: "valid_status"
    add_check_constraint :agent_execution_logs,
      "status IN ('queued', 'running', 'completed', 'failed', 'partial_success')",
      name: "valid_status"
  end

  def down
    remove_check_constraint :agent_execution_logs, name: "valid_status"
    add_check_constraint :agent_execution_logs,
      "status IN ('queued', 'running', 'completed', 'failed')",
      name: "valid_status"
  end
end
