class ReminderJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    Reminder.unsent.due_today.each do |reminder|
      reminder.send_reminder
      reminder.sent = true
      reminder.save
    end
  end
end
