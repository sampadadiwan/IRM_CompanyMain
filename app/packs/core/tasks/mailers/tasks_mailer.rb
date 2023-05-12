class TasksMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @task = Task.find params[:id]

    if @task.assigned_to
      to_emails = @task.response.blank? ? @task.assigned_to.email : [@task.assigned_to.email, @task.user&.email].compact.join(",")
      emails = sandbox_email(@task, to_emails)

      @entity = @task.entity
      cc = @entity.entity_setting.cc

      reply_to = [@entity.entity_setting.reply_to, @task.assigned_to.email, @task.user&.email, "task-#{@task.id}@#{ENV.fetch('DOMAIN', nil)}"].filter(&:present?).join(",")

      status = @task.completed ? "Closed" : "Open"

      if emails.present?
        mail(from: from_email(@task.entity),
             to: emails,
             reply_to:,
             cc:,
             subject: "Task: #{@task.id}, Status: #{status} ")
      end
    end
  end
end
