class AccessRightNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    AccessRightsMailer
  end

  def email_method(_notification = nil)
    :send_notification
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      access_right_id: record.id,
      entity_id: params[:entity_id],
      investor_id: record.access_to_investor_id
    }
  end

  notification_methods do
    def message
      @access_right ||= record
      params[:msg] || "Access granted to #{@access_right&.owner}"
    end

    def custom_notification
      nil
    end

    def url
      @access_right ||= record
      polymorphic_url(@access_right.owner_type.tableize.singularize, id: @access_right.owner_id, sub_domain: @access_right.entity.sub_domain)
    end
  end
end
