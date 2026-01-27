class TaskNotifier < BaseNotifier
  # Add required params
  required_param :entity_id

  def mailer_name(_notification = nil)
    TasksMailer
  end

  def email_method(_notification = nil)
    :send_notification
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      task_id: record&.id,
      entity_id: params[:entity_id] || record&.entity_id
    }
  end

  notification_methods do
    def message
      @task ||= record
      if @task.details.present?
        @task.details.body.to_plain_text.truncate(100)
      else
        "Task Notification"
      end
    end

    def custom_notification
      nil
    end

    def url
      task_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
