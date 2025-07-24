# app/jobs/db_restore_job.rb
class DbRestoreJob < ApplicationJob
  queue_as :db_restore
  sidekiq_options retry: false

  def perform(instance_name: 'DbCheckInstance')
    DbRestoreService.run!(instance_name: instance_name)
  rescue StandardError => e
    Rails.logger.error("[DbRestoreJob] Failed: #{e.message}")
    # optionally notify via email, Slack, Sentry, etc.
    ExceptionNotifier.notify_exception(e, data: { env: Rails.env, context: 'DbRestoreJob', instance_name: instance_name })
  end
end
