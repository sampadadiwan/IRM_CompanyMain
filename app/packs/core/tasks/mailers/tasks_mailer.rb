class TasksMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @task = Task.find params[:task_id]

    if @task.assigned_to

      status = @task.completed ? "Closed" : "Open"

      send_mail(subject: "Task: #{@task.id}, Status: #{status} ") if @to.present?
    end
  end
end
