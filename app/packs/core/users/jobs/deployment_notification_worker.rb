class DeploymentNotificationWorker
  include Sidekiq::Worker

  def perform(type, msg: nil)
    case type
    when "before"
      msg ||= "🚨 System going down for update. Downtime is 15 mins. #{Time.zone.now}"
      User.msg_todays_users(msg, level: :danger)
    when "after"
      msg ||= "✅ System is back online. Thank you for your patience. #{Time.zone.now}"
      User.msg_todays_users(msg, level: :success)
    when "adhoc"
      User.msg_todays_users(msg, level: :info) if msg.present?
    else
      Rails.logger.warn "Unknown deployment notification type: #{type}"
    end
  end
end
