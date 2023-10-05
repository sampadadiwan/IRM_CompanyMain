class BaseNotification < Noticed::Base
  deliver_by :database, format: :to_database
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", if: :whatsapp_enabled?
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  param :entity_id

  def to_database
    {
      params:,
      type: self.class.name,
      entity_id: params[:entity_id]
    }
  end

  def email_delay
    # Randomize the delay so we dont flood aws SES
    delay_seconds = entity.entity_setting.email_delay_seconds
    delay_seconds = delay_seconds.positive? ? rand(1..delay_seconds).seconds : rand(1..300).seconds
    Rails.env.development? ? 0.seconds : delay_seconds
  end

  def email_method
    params[:email_method]
  end

  def whatsapp_enabled?
    recipient.whatsapp_enabled && recipient.phone.present?
  end

  def view_path
    notification_path(id: record.id, subdomain: record.entity.sub_domain)
  end
end
