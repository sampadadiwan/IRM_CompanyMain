class TaskNotification < BaseNotification
  # Add required params
  param :task
  param :entity_id

  def mailer_name
    TasksMailer
  end

  def email_method
    :send_notification
  end

  def email_data
    {
      user_id: recipient.id,
      task_id: params[:task].id,
      entity_id: params[:entity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @task ||= params[:task]
    @task.details
  end

  def url
    task_path(id: params[:task].id)
  end
end
