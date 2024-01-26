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
    {
      params:,
      type: self.class.name,
      entity_id: params[:entity_id]
      # unique_key: self.unique_key # This is sent as the notification_id to the mailer
    }
  end

  def unique_key
    if record.nil?
      # If the record has not yet been saved, we add the current time
      params[:at] = Time.zone.now
    end
    digest = OpenSSL::Digest.new('sha256')
    # Generate a unique_key based on the recipient and the at time (Should be unique)
    OpenSSL::HMAC.hexdigest(digest, self.class.name, [params[:at], recipient.id, recipient.class.name].to_json)
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
