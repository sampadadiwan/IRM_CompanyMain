class AddTasksCsvToDealActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :deal_activities, :tasks_csv, :text
  end
end
