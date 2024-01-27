class BaseNotification < Noticed::Base
  if Rails.env.test?
    # No delay in test env
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", if: :whatsapp_enabled?
    deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data
  else
    # Randomize the delay so we dont flood aws SES / WATI
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp", if: :whatsapp_enabled?, delay: :email_delay
    deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data, delay: :email_delay
  end

  # This must be the last deliver_by, so that it gets created first when the noticed gem callbacks run
  deliver_by :database, format: :to_database

  param :entity_id

  def mailer_name
    raise NotImplementedError
  end

  def to_database
    whatsapp = whatsapp_enabled? ? {} : { "#{recipient.phone}": {whatsapp_enabled: whatsapp_enabled?} }.to_json  
    {
      params:,
      type: self.class.name,
      entity_id: params[:entity_id],
      whatsapp:
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
