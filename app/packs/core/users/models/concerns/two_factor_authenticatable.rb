module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  # Human labels for the three modes, in the order the mode-selection screen shows them.
  # Keyed by the two_factor_mode value.
  MODE_LABELS = {
    "whatsapp" => "WhatsApp",
    "sms" => "Text message",
    "authenticator" => "Authenticator app"
  }.freeze

  included do
    # otp_backup_codes is no longer used (backup codes were removed) but is NOT dropped in
    # this release. Deploys migrate before the app restarts, so dropping the column in the
    # same release as the code that stops reading it would make every old-code 2FA login
    # fail between the two steps. Step 1 (this release): ignore it. Step 2 (a later
    # release): a migration removing the column, then delete this line.
    self.ignored_columns += %w[otp_backup_codes]

    before_save :clear_two_factor_method_when_disabled
  end

  # Which modes this user could enrol in right now, as two_factor_mode values. The single
  # source for the mode-selection screen, the reset modal and the reset email, so none of
  # them can promise a method another refuses.
  #
  # @return [Array<String>]
  def available_two_factor_modes
    modes = []
    modes << "whatsapp" if whatsapp_otp_enabled?
    modes << "sms" if sms_otp_enabled?
    modes << "authenticator"
    modes
  end

  # Same list as labels for copy ("WhatsApp, Text message or Authenticator app").
  #
  # @return [Array<String>]
  def available_two_factor_mode_labels
    available_two_factor_modes.map { |mode| MODE_LABELS.fetch(mode) }
  end

  # Forgets the enrolled method without saving: mode, secret and the anti-replay
  # timestep for that secret. Called by the disable callback below and by
  # TwoFactorReset#clear_method, so there is one list of "what makes up a method".
  def forget_two_factor_method
    self.two_factor_mode = nil
    self.otp_secret = nil
    self.consumed_timestep = nil
  end

  # Switching two-factor OFF forgets the method with it.
  #
  # Without this the mode, secret and replay timestep survived the toggle. A user who
  # disabled 2FA, deleted the authenticator entry (or changed phones), and later switched
  # it back on was routed by TwoFactorDispatch straight to the code screen for a method
  # they no longer had — and while it was off the "Change 2FA Method" button was hidden,
  # so nothing let them fix it in advance. The profile toggle already promises "you can
  # choose ... on your next login", which is exactly what this makes true.
  #
  # Audited: two_factor_mode is in User's audit_fields, so the clear shows up alongside
  # the two_factor_enabled change.
  def clear_two_factor_method_when_disabled
    return unless two_factor_enabled_changed? && !two_factor_enabled?

    forget_two_factor_method
  end

  # Shows call code + masked phone, e.g. "+91 xxxxxxx805"
  def masked_phone_with_call_code
    return "" if phone.blank?
    digits = phone.to_s
    masked = "#{"x" * [digits.length - 3, 0].max}#{digits.last(3)}"
    "+#{call_code} #{masked}"
  end

  def whatsapp_mode?
    two_factor_mode == "whatsapp"
  end

  def authenticator_mode?
    two_factor_mode == "authenticator"
  end

  def sms_mode?
    two_factor_mode == "sms"
  end

  # Whether SMS two-factor is switched on for the deployment AND this user has a number
  # we can actually text.
  #
  # Both halves are required and they answer different questions: the environment switch
  # is the rollout/kill control, the number is the entitlement. Nothing is stored per
  # user or per entity — see SmsDeliverable for why.
  #
  # Used by the mode-selection screen and by the SMS fallback button on the login screen.
  def sms_otp_enabled?
    return false unless SmsDeliverable.feature_enabled?

    sms_available?
  end

  # Whether WhatsApp two-factor can actually be offered to this user.
  #
  # `whatsapp_enabled` alone is not enough. It is an administrator's assertion that the
  # user is reachable on WhatsApp, and nothing keeps it in step with `users.phone` — a
  # user can carry the flag with no number stored at all (self sign-up, an import that
  # set the flag but no phone, a number later cleared). Offering WhatsApp to such a user
  # sends them into an enrollment screen that says "code sent to +" and waits for a code
  # SendOtpToWhatsappJob has already refused to send.
  #
  # So the number is checked here, once, and the mode-selection and login screens ask
  # this instead of the raw column.
  #
  # @return [Boolean]
  def whatsapp_otp_enabled?
    whatsapp_enabled? && phone.present?
  end

  # Starts an SMS verification.
  #
  # The otp_secret is still generated even though Verify does not need it: it is what a
  # later switch to authenticator mode would use, and #create still falls back to a TOTP
  # check, which requires a secret to be present.
  def ensure_otp_secret_and_send_sms!(purpose = "enrollment")
    if otp_secret.blank?
      generate_otp_secret
      save!
    end
    send_otp_via_sms(purpose)
  end

  # No code is passed — Twilio Verify generates and holds it. Contrast
  # send_otp_via_whatsapp, which passes the live code as a job argument.
  def send_otp_via_sms(purpose = "login")
    ::SendOtpToSmsJob.perform_later(id, purpose)
  end

  # `consumed_timestep` is anti-replay bookkeeping about the OLD secret: devise-two-factor
  # passes it to ROTP as `after:`, which rejects every code from that timestep or earlier.
  # A brand new secret makes those codes unverifiable anyway, so carrying the timestep over
  # only blocks the legitimate first code — a user who verified a code and then re-enrolled
  # inside the same 30-second window is told "Invalid code. Please try again." Clear it
  # with the secret so enrollment starts from a clean slate.
  def generate_otp_secret
    self.otp_secret = User.generate_otp_secret
    self.consumed_timestep = nil
  end

  # Ensures a secret exists (generates + saves if blank), then sends current TOTP code via WhatsApp.
  # Used for whatsapp_mode enrollment and auto-send at login.
  def ensure_otp_secret_and_send_whatsapp!
    if otp_secret.blank?
      generate_otp_secret
      save!
    end
    send_otp_via_whatsapp
  end

  def send_otp_via_whatsapp
    code = current_otp # current TOTP code from devise-two-factor
    ::SendOtpToWhatsappJob.perform_later(id, code)
  end

  # We handle 2FA verification in our own TwoFactorController,
  # not through the gem's authentication strategy. This tells the
  # strategy to skip OTP validation during the initial password login.
  def otp_required_for_login
    false
  end

  # Override devise-two-factor's method to also check our flag
  def need_two_factor_authentication?(_request)
    two_factor_enabled?
  end
end
