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

  # Gates the :email deliver_by itself (see BaseNotifier) so a blank-body custom notification
  # never even enqueues the mailer job - there's nothing worth sending, and no default body to
  # fall back to. True for every notifier that has no CustomNotification concept at all (most
  # don't define `custom_notification` via `notification_methods`), or when no CustomNotification
  # is configured (nil) - only an actually-resolved-but-blank body is skipped. A Trix rich-text
  # body can save as "<div><br></div>" and still be a non-empty string, so a plain #blank? check
  # on the raw HTML isn't enough.
  def custom_notification_body_present?
    return true unless respond_to?(:custom_notification)

    cn = custom_notification
    return true if cn.nil?

    ActionView::Base.full_sanitizer.sanitize(cn.body.to_s).present?
  end

  # Gates the :whats_app deliver_by itself (see BaseNotifier) so it never even enqueues the
  # delivery job unless there's an actual message to send. Unlike custom_notification_body_present?,
  # this defaults to false (skip) when there's no CustomNotification concept at all or none is
  # configured - WhatsApp has no hardcoded default message anywhere (every mailer has one; nothing
  # sends WhatsApp content except CustomNotification#whatsapp), so "no CustomNotification" and "blank
  # whatsapp field" both mean "nothing to send" here, not just the blank-field case.
  def custom_notification_whatsapp_present?
    return false unless respond_to?(:custom_notification)

    cn = custom_notification
    return false if cn.nil?

    ActionView::Base.full_sanitizer.sanitize(cn.whatsapp.to_s).present?
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
    # Prefer the persisted column (set by ApplicationMailer#mark_delivered during delivery).
    # Falls back to deriving from event.record for notifications that predate bounce-tracking
    # columns, and for callers that don't go through mark_delivered.
    read_attribute(:entity_id).presence || (model&.entity_id if model.respond_to?(:entity_id))
  end
end

Rails.application.config.to_prepare do
  # You can extend Noticed::Event or Noticed::Notification here
  Noticed::Event.include EventExtensions
  Noticed::Notification.include NotificationExtensions

  # Ransack allowlists — must be in to_prepare so they survive dev reloads
  Noticed::Event.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[created_at type record_type record_id].sort
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end
  end

  Noticed::Notification.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[created_at user_email email_sent read_at whatsapp whatsapp_sent subject skip_reason skip_reported_at].sort
    end

    def self.ransackable_associations(_auth_object = nil)
      [:event]
    end

    ransacker :user_email, formatter: proc { |v| v.downcase } do |_parent|
      Arel.sql(<<~SQL.squish)
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
