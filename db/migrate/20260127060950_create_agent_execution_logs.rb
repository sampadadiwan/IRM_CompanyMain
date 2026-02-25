class CreateAgentExecutionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_execution_logs do |t|
      t.references :agent_schedule, foreign_key: true  # nullable for manual runs without schedule
      t.references :support_agent, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # Trigger Information
      t.string :trigger_type, limit: 20, null: false  # scheduled, manual
      t.references :triggered_by, foreign_key: { to_table: :users }  # user who triggered (for manual runs)

      # Execution Status
      t.string :status, limit: 20, null: false, default: 'queued'  # queued, running, completed, failed
      t.integer :attempt_number, null: false, default: 1  # which attempt (1, 2, 3... for retries)

      # Timing
      t.datetime :started_at
      t.datetime :completed_at

      # Results
      t.text :error_message           # error details if failed
      t.json :result_summary         # agent-specific output summary

      t.datetime :created_at, null: false
    end

    # Indexes
    add_index :agent_execution_logs, [:support_agent_id, :entity_id, :created_at],
              order: { created_at: :desc }, name: 'idx_execution_logs_history'
    add_index :agent_execution_logs, :status,
              where: "status IN ('queued', 'running')", name: 'idx_execution_logs_status'
    add_index :agent_execution_logs, [:agent_schedule_id, :created_at],
              order: { created_at: :desc }, name: 'idx_execution_logs_schedule'

    # Check constraints (wrapped in reversible for proper rollback)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE agent_execution_logs
          ADD CONSTRAINT valid_trigger_type CHECK (trigger_type IN ('scheduled', 'manual'));
        SQL

        execute <<-SQL
          ALTER TABLE agent_execution_logs
          ADD CONSTRAINT valid_status CHECK (status IN ('queued', 'running', 'completed', 'failed'));
        SQL

        execute <<-SQL
          ALTER TABLE agent_execution_logs
          ADD CONSTRAINT valid_attempt_number CHECK (attempt_number >= 1);
        SQL
      end

      dir.down do
        execute "ALTER TABLE agent_execution_logs DROP CONSTRAINT IF EXISTS valid_trigger_type"
        execute "ALTER TABLE agent_execution_logs DROP CONSTRAINT IF EXISTS valid_status"
        execute "ALTER TABLE agent_execution_logs DROP CONSTRAINT IF EXISTS valid_attempt_number"
      end
    end
  end
end
