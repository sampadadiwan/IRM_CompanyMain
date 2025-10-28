class ApplicationJob < ActiveJob::Base
  sidekiq_options backtrace: 20
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

  def send_errors_notification(main_error, error_msg, user_id, _level = "success")
    @show_btn = true
    @error_msg = error_msg
    @user_id = user_id
    @main_error = main_error

    # Render the /entity_mailer/doc_gen_errors email template and capture the output as a string
    msg = ApplicationController.render(
      template: "entity_mailer/doc_gen_errors",
      assigns: { main_error: @main_error, error_msg: @error_msg, user_id: @user_id, show_btn: @show_btn },
      layout: false
    )
    send_notification(msg, user_id, "danger")
  end

  def self.run_from_console(queue = "default")
    # Get the last job enqueued (from the default queue, change if needed)
    job = Sidekiq::Queue.new(queue).to_a.first

    if job.present?
      # Inspect it
      job.klass      # => Worker class name
      job.args       # => Arguments passed
      job.enqueued_at

      # Run it immediately in the console
      job.klass.constantize.new.perform(*job.args)
    else
      Rails.logger.debug { "No jobs in the #{queue} queue" }
    end
  end
end
