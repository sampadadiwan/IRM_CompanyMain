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

  # Security notification: a two-factor method was just confirmed with a code, so sign-in now
  # asks for one (Users::TwoFactorController#commit_method!). Sent for every confirmed method —
  # a support / super user's required set-up (H2) and anyone's voluntary one alike — so the owner
  # hears about an enrolment they did not make. Not a CustomNotification: it must always go out and
  # must not be editable per firm (require-2fa-privileged-roles design D10).
  #
  # @param entity_id [Integer] / user_id [Integer] — ApplicationMailer#setup_defaults keys on these
  # @param mode [String] "authenticator" / "whatsapp" / "sms"
  def two_factor_enabled
    # The label the user picked on the set-up screen, e.g. "Authenticator app"
    @mode_label = TwoFactorAuthenticatable::MODE_LABELS.fetch(params[:mode].to_s, params[:mode].to_s.titleize)

    mail(from: @from, to: @to, subject: "Two-factor authentication was turned on for your account")
  end

  # Security notification: the user turned two-factor OFF with their password and a current code
  # (TwoFactorDisable, H9 / H10). Confirms the change, or warns them about one they never made.
  #
  # @param entity_id [Integer] / user_id [Integer] — ApplicationMailer#setup_defaults keys on these
  # @param previous_mode [String, nil] the method that stopped being asked for (nil: none was set up, E30)
  def two_factor_disabled
    @previous_mode_label = previous_mode_label(params[:previous_mode])

    mail(from: @from, to: @to, subject: "Two-factor authentication was turned off for your account")
  end

  # Tells one of the firm's OTHER company admins that a colleague's two-factor was turned off
  # (TwoFactorDisable, event "disabled") or that an administrator reset a colleague's method
  # (TwoFactorReset, event "reset"). One email per admin, so each goes through setup_defaults with
  # their own user_id (sandbox-aware); the colleague is passed separately as subject_user_id.
  #
  # @param user_id [Integer] the admin receiving this email
  # @param subject_user_id [Integer] the user whose two-factor changed
  # @param actor_id [Integer] who made the change
  # @param event [String] "disabled" or "reset"
  def two_factor_admin_notice
    # Who changed, and who changed it — reloaded from ids, never passed as objects
    @subject_user = User.find(params[:subject_user_id])
    @actor = User.find_by(id: params[:actor_id])
    @event = params[:event].to_s

    subject = if @event == "reset"
                "Two-factor method reset for #{@subject_user.full_name}"
              else
                "Two-factor was turned off for #{@subject_user.full_name}"
              end
    mail(from: @from, to: @to, subject:)
  end

  # The code that confirms a change to the user's existing mobile number. Sent only by
  # SendPhoneChangeCodeJob, with deliver_now inside the job, so the plain code never sits in a
  # job queue. The code is in the body only, never the subject (subjects show in lock-screen
  # previews and mail logs).
  #
  # @param entity_id [Integer] / user_id [Integer] — ApplicationMailer#setup_defaults keys on these
  # @param actor_id [Integer] who started the change (same as user_id for self-service)
  # @param code [String] the 6-digit code
  # @param request_id [Integer] the PhoneChangeRequest, for the new number and expiry
  def phone_change_code
    @actor = User.find_by(id: params[:actor_id])
    @self_change = @actor.present? && @actor.id == @user.id
    @code = params[:code]
    @request = PhoneChangeRequest.find(params[:request_id])

    mail(from: @from, to: @to, subject: "Confirm your mobile number change")
  end

  # Security notification after the number changed (PhoneChangeConfirm). Confirms a change
  # the user made, or warns them about one they never asked for.
  #
  # @param previous_masked_phone [String] the old number, masked
  def phone_changed
    @actor = User.find_by(id: params[:actor_id])
    @self_change = @actor.present? && @actor.id == @user.id
    @previous_masked_phone = params[:previous_masked_phone]

    mail(from: @from, to: @to, subject: "Your mobile number was changed")
  end

  private

  # "Authenticator app" for "authenticator"; nil when no method had been set up
  def previous_mode_label(mode)
    return nil if mode.blank?

    TwoFactorAuthenticatable::MODE_LABELS.fetch(mode.to_s, mode.to_s.titleize)
  end
end
