class AccessRightNotifier < BaseNotifier
  # Add required params
  required_param :access_right

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
      access_right_id: params[:access_right].id,
      entity_id: params[:entity_id]
    }
  end

  notification_methods do
    def message
      @access_right ||= params[:access_right]
      params[:msg] || "Access granted to #{@access_right.owner}"
    end

    def custom_notification
      nil
    end

    def url
      @access_right ||= params[:access_right]
      polymorphic_url(@access_right.owner_type.tableize.singularize, id: @access_right.owner_id)
    end
  end
end
