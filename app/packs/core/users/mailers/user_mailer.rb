class UserMailer < ApplicationMailer
  # Align the stated TTL with the actual signed_id expiry in the template (both 10 minutes).
  # Security fix (Finding 6): the original subject said "5 minutes" but the token lasted 15,
  # leaving an undisclosed extra window during which an intercepted link could be replayed.
  MAGIC_LINK_TTL = 10.minutes

  def magic_link
    @user = User.find params[:id]
    @current_entity = Entity.where(id: params[:current_entity_id]).first if params[:current_entity_id].present?

    # Security fix (Finding 7): params[:redirect_to] is no longer passed to the mailer.
    # The email template no longer embeds a redirect destination in the link URL.
    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Login Link: Expires in #{MAGIC_LINK_TTL.in_minutes.to_i} minutes")
  end

  # Security fix (Finding 3 — email enumeration): sent when the submitted address is not
  # registered, so the controller can return an identical HTTP response regardless of whether
  # the email exists. The person who submitted the address (if they genuinely own it) learns
  # via this email that no account was found, which is useful feedback without revealing
  # anything in the HTTP response that an attacker could observe at scale.
  def no_account_found
    @email = params[:email]
    mail(from: ENV.fetch("SUPPORT_EMAIL_FROM", "noreply@example.com"),
         to: @email,
         subject: "Login request received — no account found")
  end

  def audit_download
    @user = User.find params[:user_id]
    attachments['audits.xlsx'] = { mime_type: 'application/xlsx', content: params[:file].read }
    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Audit Download")
  end

  # Generic model download email
  # @param user_id [Integer] The user to send to
  # @param entity_id [Integer] The entity for branding
  # @param file [Tempfile] The file to attach
  # @param filename [String] The filename for the attachment
  def model_download
    @model_name = params[:model_name] || 'Model'
    filename = params[:filename] || 'download.xlsx'
    file = params[:document].file.download
    attachments[filename] = { mime_type: 'application/xlsx', content: file.read }
    subject = params[:message] || "Your Download is Ready: #{filename}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end
end
