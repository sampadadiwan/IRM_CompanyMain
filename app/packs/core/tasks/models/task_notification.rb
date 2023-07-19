# To deliver this notification:
#
# TaskNotification.with(task_id: @task.id).deliver_later(current_user)
# TaskNotification.with(task_id: @task.id).deliver(current_user)

class TaskNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "TasksMailer", method: :send_notification
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"
  # Add required params
  param :task_id

  # Define helper methods to make rendering easier.
  def message
    @task ||= Task.find(params[:task_id])
    @task.details
  end

  def url
    task_path(id: params[:task_id])
  end
end
