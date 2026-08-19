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

  # Security notification sent by TwoFactorReset after a user's two-factor METHOD was cleared
  # back to "none". Goes out for both the self-service and the administrator path — in the
  # first case it confirms the action, in the second it is the user's warning if they never
  # asked for it. `actor_id` tells the template which of the two wording variants to use.
  #
  # @param entity_id [Integer] the user's entity — ApplicationMailer#setup_defaults derives
  #   @from / @to (sandbox-aware) from entity_id + user_id
  # @param user_id [Integer] the user whose method was reset (becomes @user)
  # @param actor_id [Integer] who performed the reset (same as user_id for self-service)
  # @param previous_mode [String] "authenticator" / "whatsapp" / "sms" — for the email body
  # @param message [String, nil] optional note typed by the administrator in the modal
  def two_factor_reset
    @actor = User.find_by(id: params[:actor_id])
    @self_reset = @actor.present? && @actor.id == @user.id
    @previous_mode = params[:previous_mode].to_s
    @message = params[:message]

    mail(from: @from, to: @to, subject: "Your two-factor authentication method was reset")
  end
end
