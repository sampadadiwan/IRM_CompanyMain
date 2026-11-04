# Tells a company's admins, once per transition, that Zoho rejected their account's credentials and
# documents can't be sent through it until someone reconnects (design: Notifications).
class ZohoSignConnectionNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    EntityMailer
  end

  def email_method(_notification = nil)
    :zoho_sign_needs_reconnect
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      zoho_sign_connection_id: record.id
    }
  end

  notification_methods do
    def message
      "#{record.entity.name}'s Zoho eSign account needs to be reconnected"
    end

    def custom_notification
      nil
    end

    def url
      Rails.application.routes.url_helpers.entity_path(record.entity_id, sub_domain: record.entity.sub_domain)
    end
  end
end
