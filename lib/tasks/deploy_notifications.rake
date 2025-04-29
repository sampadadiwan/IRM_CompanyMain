# lib/tasks/deploy_notifications.rake
namespace :deploy do
    desc "Notify users that system will go down (before deploy)"
    task notify_before: :environment do
      puts "🚨 Enqueueing pre-deployment notification..."
      if defined?(DeploymentNotificationWorker)
        DeploymentNotificationWorker.perform_async("before")
        puts "✅ Pre-deployment notification enqueued."
      else
        Rails.logger.warn "⚠️ DeploymentNotificationWorker not defined. Skipping pre-deployment notification."
      end
    end
  
    desc "Notify users that system is back (after deploy)"
    task notify_after: :environment do
      puts "✅ Enqueueing post-deployment notification..."
      if defined?(DeploymentNotificationWorker)
        DeploymentNotificationWorker.perform_in(1.minute, "after")
        puts "✅ Post-deployment notification enqueued."
      else
        Rails.logger.warn "⚠️ DeploymentNotificationWorker not defined. Skipping post-deployment notification."
      end
    end
end
  