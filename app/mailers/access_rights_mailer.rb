class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper
  
  def notify_access
    @access_right = AccessRight.includes(:owner, :investor).find params[:access_right_id]

    # We need to figure out all the users impacted by this access right

    emails = @access_right.investor_emails

    if emails.present?
      mail(to: ENV['SUPPORT_EMAIL'],
           bcc: emails,
           cc: ENV['SUPPORT_EMAIL'],
           subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
    end
  end
end
