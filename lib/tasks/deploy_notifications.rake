namespace :deploy do
    desc "Notify users before deployment"
    task notify_before: :environment do
      puts "🚨 Sending pre-deployment notice to today's users..."
      User.msg_todays_users("🚨 System going down for update at 9:00pm IST. Downtime is 15 mins", level: :danger)
    end
  
    desc "Notify users after deployment"
    task notify_after: :environment do
      puts "✅ Sending post-deployment notice to today's users..."
      User.msg_todays_users("✅ System is back online. Thank you for your patience.", level: :success)
    end
end
  