class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_access
    # We need to figure out all the users impacted by this access right
    @access_right = AccessRight.includes(:owner, :investor).find params[:access_right_id]

    if @access_right
      # Only send to confirmed users
      confirmed_emails = User.where(email: @access_right.investor_emails).where.not(confirmed_at: nil).collect(&:email).join(",")

      if confirmed_emails.present?
        if @access_right.access_to_category.present?
          bcc = sandbox_email(@access_right, confirmed_emails)
          to = ENV.fetch('SUPPORT_EMAIL', nil)
        else
          to = sandbox_email(@access_right, confirmed_emails)
          bcc = nil
        end

        mail(from: from_email(@access_right.entity),
             to:,
             bcc:,
             subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
      end
    else
      Rails.logger.debug { "Could not find access right with id #{params[:access_right_id]}" }
    end
  end
end
