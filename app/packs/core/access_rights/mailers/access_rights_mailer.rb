class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper

  def send_notification
    @access_right = AccessRight.includes(:owner, :investor).find(params[:access_right_id])

    send_mail(subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
  end
end
