class AddNoteToReminder < ActiveRecord::Migration[7.0]
  def change
    add_column :reminders, :note, :text
    add_column :reminders, :due_date, :date
    add_column :reminders, :email, :string
    remove_column :reminders, :unit
    remove_column :reminders, :count
  end
end
