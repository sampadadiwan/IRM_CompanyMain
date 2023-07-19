class BaseNotification < Noticed::Base
  deliver_by :database, format: :to_database
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  param :entity_id

  def to_database
    {
      params:,
      type: self.class.name,
      entity_id: params[:entity_id]
    }
  end

  def email_method
    params[:email_method]
  end

  def view_path
    notification_path(id: record.id, subdomain: record.entity.sub_domain)
  end
end
