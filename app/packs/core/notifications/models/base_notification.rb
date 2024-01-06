class BaseNotification < Noticed::Base
  deliver_by :database, format: :to_database
  if Rails.env.test?
    # No delay in test env
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", if: :whatsapp_enabled?
    deliver_by :whats_app_logger, class: "DeliveryMethods::WhatsAppLogger", unless: :whatsapp_enabled?
    deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data
    deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"
  else
    # Randomize the delay so we dont flood aws SES / WATI
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", if: :whatsapp_enabled?, delay: :email_delay
    deliver_by :whats_app_logger, class: "DeliveryMethods::WhatsAppLogger", unless: :whatsapp_enabled? # no delay for logger
    deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data, delay: :email_delay
    deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts", delay: :email_delay
  end

  param :entity_id

  def mailer_name
    raise NotImplementedError
  end

  def to_database
    {
      params:,
      type: self.class.name,
      entity_id: params[:entity_id]
    }
  end

  def email_delay
    # Randomize the delay so we dont flood aws SES
    delay_seconds = record.entity.entity_setting.email_delay_seconds
    delay_seconds = delay_seconds.positive? ? rand(1..delay_seconds).seconds : rand(1..300).seconds
    Rails.env.development? ? 0.seconds : delay_seconds
  end

  def email_method
    params[:email_method]
  end

  def whatsapp_enabled?
    recipient.whatsapp_enabled && recipient.phone.present? && !Rails.env.test?
  end

  def view_path
    notification_path(id: record.id, subdomain: record.entity.sub_domain)
  end
end
