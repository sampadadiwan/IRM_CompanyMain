class ReminderMailer < ApplicationMailer
  helper ApplicationHelper

  def send_reminder
    @reminder = Reminder.find params[:reminder_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@reminder, @user.email)
    subject = "Reminder: #{@reminder.note}"
    mail(from: from_email(@reminder.entity),
         to: emails,
         subject:)
  end
end
