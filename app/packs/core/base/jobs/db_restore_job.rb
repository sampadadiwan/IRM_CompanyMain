# app/jobs/db_restore_job.rb
class DbRestoreJob < ApplicationJob
  queue_as :db_restore
  sidekiq_options retry: false

  def perform(instance_name: 'DbCheckInstance')
    DbRestoreService.run!(instance_name: instance_name)
  rescue StandardError => e
    msg = "✗ DbRestoreJob failed: #{e.message}"
    Rails.logger.error(msg)
    # optionally notify via email, Slack, Sentry, etc.
    notify_errors(msg)
  end

  def notify_errors(msg)
    EntityMailer.with(subject: "#{Rails.env}: DB Check FAILED", msg: { process: "DB RESTORE CHECK", result: "FAILED", message: msg }).notify_info.deliver_now
  end
end
