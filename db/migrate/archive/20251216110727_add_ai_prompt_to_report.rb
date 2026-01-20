class AddAiPromptToReport < ActiveRecord::Migration[8.0]
  def up
    unless column_exists? :reports, :ai_prompt
      add_column :reports, :ai_prompt, :text
    end
    unless column_exists? :reports, :send_notification
      add_column :reports, :send_notification, :boolean, default: false
    end
    unless column_exists? :reports, :notification_recipients
      add_column :reports, :notification_recipients, :string
    end
    unless column_exists? :reports, :notification_ccs
      add_column :reports, :notification_ccs, :string
    end
    unless column_exists? :reports, :notification_start_after
      add_column :reports, :notification_start_after, :integer, default: 0
    end
    unless column_exists? :reports, :notification_start_unit
      add_column :reports, :notification_start_unit, :string, default: "days"
    end
    unless column_exists? :reports, :notification_repeat_interval
      add_column :reports, :notification_repeat_interval, :integer, default: 1
    end
    unless column_exists? :reports, :notification_repeat_unit
      add_column :reports, :notification_repeat_unit, :string, default: "days"
    end
    unless column_exists? :reports, :notify_next_run_at
      add_column :reports, :notify_next_run_at, :datetime
    end
    unless column_exists? :reports, :notify_last_run_at
      add_column :reports, :notify_last_run_at, :datetime
    end
    unless index_exists? :reports, :notify_next_run_at
      add_index :reports, :notify_next_run_at
    end
  end


  def down
    remove_column :reports, :ai_prompt if column_exists? :reports, :ai_prompt
    remove_column :reports, :send_notification if column_exists? :reports, :send_notification
    remove_column :reports, :notification_recipients if column_exists? :reports, :notification_recipients
    remove_column :reports, :notification_ccs if column_exists? :reports, :notification_ccs
    remove_column :reports, :notification_start_after if column_exists? :reports, :notification_start_after
    remove_column :reports, :notification_start_unit if column_exists? :reports, :notification_start_unit
    remove_column :reports, :notification_repeat_interval if column_exists? :reports, :notification_repeat_interval
    remove_column :reports, :notification_repeat_unit if column_exists? :reports, :notification_repeat_unit
    remove_column :reports, :notify_next_run_at if column_exists? :reports, :notify_next_run_at
    remove_column :reports, :notify_last_run_at if column_exists? :reports, :notify_last_run_at
    remove_index :reports, :notify_next_run_at if index_exists? :reports, :notify_next_run_at
  end
end
