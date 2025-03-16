class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  def send_notification(message, user_id, level = "success")
    if level == "danger"
      Rails.logger.error { message }
    else
      Rails.logger.debug { message }
    end
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end
end
