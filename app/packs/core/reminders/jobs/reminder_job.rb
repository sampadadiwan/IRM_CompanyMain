class ReminderJob < ApplicationJob
  queue_as :low

  def perform(*_args)
    Chewy.strategy(:sidekiq) do
      Reminder.unsent.due_today.each do |reminder|
        reminder.send_reminder
        reminder.sent = true
        reminder.save
      end
    end
  end
end
