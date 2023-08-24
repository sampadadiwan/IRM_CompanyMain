class TaskNotification < BaseNotification
  deliver_by :email, mailer: "TasksMailer", method: :send_notification
  # Add required params
  param :task

  # Define helper methods to make rendering easier.
  def message
    @task ||= params[:task]
    @task.details
  end

  def url
    task_path(id: params[:task].id)
  end
end
