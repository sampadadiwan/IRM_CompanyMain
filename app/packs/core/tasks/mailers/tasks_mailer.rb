class TasksMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_task
  def set_task
    @task = Task.find params[:task_id]
  end

  def send_notification
    status = @task.completed ? "Closed" : "Open"
    subject = @task.details.present? ? @task.details.body.to_plain_text.truncate(100) : "Task: #{@task.id}"
    send_mail(subject: subject + ", Status: #{status}")
  end
end
