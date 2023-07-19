class AccessRightNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "AccessRightsMailer", method: :send_notification, format: :email_data, delay: rand(30).seconds

  # Add required params
  param :access_right_id

  def email_data
    {
      user_id: recipient.id,
      access_right_id: params[:access_right_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @access_right ||= AccessRight.find(params[:access_right_id])
    params[:msg] || "Access granted to #{@access_right.owner}"
  end

  def url
    @access_right ||= AccessRight.find(params[:access_right_id])
    polymorphic_url(@access_right.owner_type.tableize.singularize, id: @access_right.owner_id)
  end
end
