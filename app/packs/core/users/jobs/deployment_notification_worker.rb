class DeploymentNotificationWorker
    include Sidekiq::Worker
  
    def perform(type)
      case type
      when "before"
        User.msg_todays_users("🚨 System going down for update. Downtime is 15 mins", level: :danger)
      when "after"
        User.msg_todays_users("✅ System is back online. Thank you for your patience.", level: :success)
      else
        Rails.logger.warn "Unknown deployment notification type: #{type}"
      end
    end
end
  