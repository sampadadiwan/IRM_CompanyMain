class AccessRightsMailer < ApplicationMailer
  helper ApplicationHelper
  MAX_TO_SIZE = 40

  def notify_access
    # We need to figure out all the users impacted by this access right
    access_right_id = params[:access_right_id]
    @access_right = AccessRight.includes(:owner, :investor).find(access_right_id)

    if @access_right
      # Only send to confirmed users
      confirmed_emails = User.where(email: @access_right.investor_emails).where.not(confirmed_at: nil).collect(&:email)

      # There is a limit of 50 emails in to or bcc field, sometimes we have more that that number to send to, hence batch
      confirmed_emails.each_slice(MAX_TO_SIZE) do |list|
        AccessRightsMailer.with(access_right_id:, list:).send_notification.deliver_later
      end

    else
      Rails.logger.debug { "Could not find access right with id #{params[:access_right_id]}" }
    end
  end

  def send_notification
    confirmed_emails = params[:list]&.join(",")

    if confirmed_emails.present?

      access_right_id = params[:access_right_id]
      @access_right = AccessRight.includes(:owner, :investor).find(access_right_id)

      to = sandbox_email(@access_right, confirmed_emails)
      bcc = (ENV.fetch('SUPPORT_EMAIL', nil) if @access_right.access_to_category.present?)

      mail(from: from_email(@access_right.entity),
           to:,
           bcc:,
           subject: "Access Granted to #{@access_right.owner_type} #{@access_right.owner.name} by #{@access_right.entity.name}")
    end
  end
end
