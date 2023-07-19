class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper

  def send_notification
    confirmed_emails = [User.find(params[:user_id]).email]

    if confirmed_emails.present?

      access_right_id = params[:access_right_id]
      @access_right = AccessRight.includes(:owner, :investor).find(access_right_id)

      to = sandbox_email(@access_right, confirmed_emails)
      cc = @access_right.entity.entity_setting.cc
      mail(from: from_email(@access_right.entity),
           to:,
           cc:,
           reply_to: cc,
           subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
    end
  end
end
