class ReminderMailer < ApplicationMailer
  helper ApplicationHelper

  def send_reminder
    @reminder = Reminder.find params[:reminder_id]
    subject = "Reminder: #{@reminder.note}"
    send_mail(subject:)
  end
end
