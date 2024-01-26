class AccessRightNotification < BaseNotification
  # Add required params
  param :access_right

  def mailer_name
    AccessRightsMailer
  end

  def email_method
    :send_notification
  end

  def email_data
    {
      notification_id: record.id,
      user_id: recipient.id,
      access_right_id: params[:access_right].id,
      entity_id: params[:entity_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @access_right ||= params[:access_right]
    params[:msg] || "Access granted to #{@access_right.owner}"
  end

  def url
    @access_right ||= params[:access_right]
    polymorphic_url(@access_right.owner_type.tableize.singularize, id: @access_right.owner_id)
  end
end
