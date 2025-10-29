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
    EntityMailer.with(subject: "#{Rails.env}: DbRestoreJob FAILED", msg: { process: "DbRestoreJob", result: "FAILED", message: msg, instance_name: instance_name }).notify_info.deliver_now
  end
end
