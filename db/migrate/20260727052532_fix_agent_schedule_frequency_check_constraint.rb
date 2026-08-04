# frozen_string_literal: true

# Rewrites all CHECK constraints on agent_execution_logs and agent_schedules
# using database-agnostic SQL. The originals single-quoted column names,
# which SQLite treats as string literals instead of column references.
class FixAgentScheduleFrequencyCheckConstraint < ActiveRecord::Migration[8.0]
  def up
    # agent_execution_logs
    remove_check_constraint :agent_execution_logs, name: "valid_attempt_number"
    remove_check_constraint :agent_execution_logs, name: "valid_status"
    remove_check_constraint :agent_execution_logs, name: "valid_trigger_type"

    add_check_constraint :agent_execution_logs,
      "attempt_number >= 1", name: "valid_attempt_number"
    add_check_constraint :agent_execution_logs,
      "status IN ('queued','running','completed','failed','partial_success')", name: "valid_status"
    add_check_constraint :agent_execution_logs,
      "trigger_type IN ('scheduled','manual')", name: "valid_trigger_type"

    # agent_schedules
    remove_check_constraint :agent_schedules, name: "valid_retry_count"
    remove_check_constraint :agent_schedules, name: "valid_retry_interval"
    remove_check_constraint :agent_schedules, name: "valid_run_on_day"
    remove_check_constraint :agent_schedules, name: "valid_frequency"

    add_check_constraint :agent_schedules,
      "retry_count >= 0", name: "valid_retry_count"
    add_check_constraint :agent_schedules,
      "retry_interval_minutes >= 0", name: "valid_retry_interval"
    add_check_constraint :agent_schedules,
      "(run_on_day IS NULL) OR ((run_on_day >= 0) AND (run_on_day <= 31))", name: "valid_run_on_day"
    add_check_constraint :agent_schedules,
      "frequency IN ('daily','weekly','monthly','bimonthly','quarterly','half_yearly')", name: "valid_frequency"
  end

  def down
    # No-op — corrected constraints are valid on both MySQL and SQLite
  end
end
