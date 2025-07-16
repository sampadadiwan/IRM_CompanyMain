# app/jobs/db_restore_job.rb
class DbRestoreJob < ApplicationJob
  queue_as :default

  def perform(instance_name: 'DbCheckInstance')
    DbRestoreService.run!(instance_name: instance_name)
  rescue StandardError => e
    Rails.logger.error("[DbRestoreJob] Failed: #{e.message}")
    # optionally notify via email, Slack, Sentry, etc.
    ExceptionNotifier.notify_exception(e, data: { context: 'DbRestoreJob', instance_name: instance_name })
  end
end
