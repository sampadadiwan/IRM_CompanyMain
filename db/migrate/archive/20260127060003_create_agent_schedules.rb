class CreateAgentSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_schedules do |t|
      t.references :support_agent, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # Schedule Configuration
      t.string :frequency, limit: 20, null: false  # daily, weekly, monthly, bimonthly, quarterly, half_yearly
      t.integer :run_on_day                        # 0-6 for weekly (0=Sunday), 1-31 for monthly
      t.time :run_at_time, null: false             # e.g., '09:00:00'
      t.string :timezone, limit: 50, null: false   # e.g., 'Asia/Kolkata'

     # Calculated Run Times (stored in UTC)
      t.datetime :next_run_at
      t.datetime :last_run_at

      # Status
      t.boolean :enabled, default: false, null: false

      # Retry Configuration
      t.integer :retry_count, default: 0, null: false
      t.integer :retry_interval_minutes, null: false, default: 0

      # Notification Configuration
      t.boolean :notify_on_failure, null: false, default: true
      t.json :failure_notification_user_ids

      # Audit
      t.references :created_by, foreign_key: { to_table: :users }
      
      t.timestamps
    end


    # Constraints and Indexes
    add_index :agent_schedules, [:support_agent_id, :entity_id], unique: true, name: 'idx_unique_agent_entity'
    add_index :agent_schedules, [:next_run_at, :enabled], where: 'enabled = true', name: 'idx_agent_schedules_polling'

    # Check constraints (wrapped in reversible for proper rollback)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE agent_schedules
          ADD CONSTRAINT valid_frequency CHECK (frequency IN ('daily', 'weekly', 'monthly', 'bimonthly', 'quarterly', 'half_yearly'));
        SQL

        execute <<-SQL
          ALTER TABLE agent_schedules
          ADD CONSTRAINT valid_run_on_day CHECK (run_on_day IS NULL OR (run_on_day >= 0 AND run_on_day <= 31));
        SQL

        execute <<-SQL
          ALTER TABLE agent_schedules
          ADD CONSTRAINT valid_retry_count CHECK (retry_count >= 0);
        SQL

        execute <<-SQL
          ALTER TABLE agent_schedules
          ADD CONSTRAINT valid_retry_interval CHECK (retry_interval_minutes >= 0);
        SQL
      end

      dir.down do
        execute "ALTER TABLE agent_schedules DROP CONSTRAINT IF EXISTS valid_frequency"
        execute "ALTER TABLE agent_schedules DROP CONSTRAINT IF EXISTS valid_run_on_day"
        execute "ALTER TABLE agent_schedules DROP CONSTRAINT IF EXISTS valid_retry_count"
        execute "ALTER TABLE agent_schedules DROP CONSTRAINT IF EXISTS valid_retry_interval"
      end
    end
  end
end
