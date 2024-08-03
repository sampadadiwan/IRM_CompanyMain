# config/initializers/noticed.rb
module EventExtensions
  extend ActiveSupport::Concern
  included do
    belongs_to :entity, optional: true
  end
end

module NotificationExtensions
  extend ActiveSupport::Concern

  def email_delay
    entity = event.entity
    # Randomize the delay so we dont flood aws SES
    delay_seconds = entity.entity_setting.email_delay_seconds
    delay_seconds = delay_seconds.positive? ? rand(1..delay_seconds) : rand(1..300)
    Rails.env.development? ? 0 : delay_seconds
  end

  def model
    params[:"#{self.class.name.split('::').first.sub('Notifier', '').underscore}"]
  end
end

Rails.application.config.after_initialize do
  Rails.logger.debug "Patching Noticed::Notification"

  module Noticed
    class Notification < ApplicationRecord
      def self.ransackable_attributes(_auth_object = nil)
        %w[created_at user_email email_sent read_at whatsapp whatsapp_sent].sort
      end

      def self.ransackable_associations(_auth_object = nil)
        []
      end

      ransacker :user_email, formatter: proc { |v| v.downcase } do |_parent|
        Arel.sql(<<-SQL.squish)
          CASE
            WHEN noticed_notifications.recipient_type = 'User' THEN (
              SELECT LOWER(users.email)
              FROM users
              WHERE users.id = noticed_notifications.recipient_id
            )
          END
        SQL
      end
    end
  end
end

Rails.application.config.to_prepare do
  # You can extend Noticed::Event or Noticed::Notification here
  Noticed::Event.include EventExtensions
  Noticed::Notification.include NotificationExtensions
end
