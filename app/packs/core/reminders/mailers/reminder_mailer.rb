class ReminderMailer < ApplicationMailer
  helper ApplicationHelper

  def send_reminder
    @reminder = Reminder.find params[:id]
    emails = sandbox_email(@reminder, @reminder.email)
    subject = "Reminder: #{@reminder.note}"
    mail(from: from_email(@reminder.entity),
         to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end
end
