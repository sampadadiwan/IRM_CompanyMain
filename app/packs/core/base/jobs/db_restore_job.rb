# app/jobs/db_restore_job.rb
class DbRestoreJob < ApplicationJob
  queue_as :db_restore
  sidekiq_options retry: false

  def perform(instance_name: 'DbCheckInstance')
    DbRestoreService.run!(instance_name: instance_name)
  rescue StandardError => e
    Rails.logger.error("✗ DbRestoreJob failed (attempt 1): #{e.message}")
    retry_with_fresh_instance(instance_name, e)
  end

  # The DbCheckInstance disk fills up over days of reuse (it is only stopped, never
  # terminated, between runs), which makes scp/restore fail. Terminate the stale
  # instance so run! launches a fresh one with a clean disk, then try once more.
  # Only if that second attempt also fails do we notify.
  def retry_with_fresh_instance(instance_name, first_error)
    Rails.logger.info("→ DbRestoreJob retrying with a fresh instance after: #{first_error.message}")
    DbRestoreService.terminate_instance!(instance_name: instance_name)
    DbRestoreService.run!(instance_name: instance_name)
  rescue StandardError => e
    msg = "✗ DbRestoreJob failed after retry: #{e.message} (first attempt: #{first_error.message})"
    Rails.logger.error(msg)
    # optionally notify via email, Slack, Sentry, etc.
    notify_errors(msg)
  end

  def notify_errors(msg)
    EntityMailer.with(subject: "#{ENV.fetch('BASE_DOMAIN', nil)}: DB Check FAILED", msg: { process: "DB RESTORE CHECK", result: "FAILED", message: msg }).notify_info.deliver_now
  end
end
