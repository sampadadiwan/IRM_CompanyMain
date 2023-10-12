class ResendConfirmationJob < ApplicationJob
  queue_as :low
  SEND_ON_DAYS = [3, 7].freeze
  def perform
    today = Time.zone.today
    one_week_ago = today - 1.week
    # Get the users who were created either 3 days ago or one week ago
    User.where(created_at: one_week_ago.., confirmed_at: nil).find_each do |user|
      days_since = (today - user.created_at.to_date).to_i
      Rails.logger.debug { "#{user.email} is not confirmed, days_since created = #{days_since}" }
      user.send_confirmation_instructions if SEND_ON_DAYS.include?(days_since)
    end
    nil
  end
end
