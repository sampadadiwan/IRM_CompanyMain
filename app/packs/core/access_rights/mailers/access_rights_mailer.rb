class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    # We need to figure out all the users impacted by this access right
    @access_right = AccessRight.includes(:owner, :investor).find params[:access_right_id]
    # Only send to confirmed users
    confirmed_emails = User.where(email: @access_right.investor_emails).where.not(confirmed_at: nil)

    emails = sandbox_email(@access_right, confirmed_emails)

    if emails.present?
      mail(from: from_email(@access_right.entity),
           to: ENV['SUPPORT_EMAIL'],
           bcc: emails,
           subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
    end
  end
end
