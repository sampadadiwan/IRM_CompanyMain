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

  def investor_access
    if model.respond_to?(:investor) && model.investor.present?
      model.investor.investor_accesses.where(user_id: recipient.id).first
    else
      model.entity.investor_accesses.where(user_id: recipient.id).first
    end
  end

  def email_enabled
    # Either the recipient belongs to the model entity or the investor_access email_enabled is true
    model.entity_id == recipient.entity_id ||
      investor_access&.email_enabled
  end

  def whatsapp_enabled
    model.entity.permissions.enable_whatsapp? && # Is WA enabled for the entity
      (
        model.entity_id == recipient.entity_id ||
        (investor_access&.whatsapp_enabled && # Is WA enabled for the investor access specified by the entity
        recipient.whatsapp_enabled && # Is WA enabled for the recipient
        recipient.phone.present?) # Does the recipient have a phone number
      )
  end

  def model
    # The new way is to store the record in the event
    # The old way was to store the record in params

    # The actual model is stored in params
    # The key is model name in lowercase
    # To get the model name, we use the notifier name and remove the Notifier part
    event.record.presence || params[:"#{self.class.name.split('::').first.gsub('Notifier', '').gsub('Download', '').underscore}"]
  end

  def entity_id
    model&.entity_id if model.respond_to?(:entity_id)
  end
end

Rails.application.config.after_initialize do
  Rails.logger.debug "Patching Noticed::Notification"

  module Noticed
    class Notification < ApplicationRecord
      def self.ransackable_attributes(_auth_object = nil)
        %w[created_at user_email email_sent read_at whatsapp whatsapp_sent subject].sort
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
