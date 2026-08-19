require 'bcrypt'

module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

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

  def generate_backup_codes!
    codes = 8.times.map { SecureRandom.hex(4).upcase.insert(4, '-') }
    hashed = codes.map { |c| ::BCrypt::Password.create(c) }
    update!(otp_backup_codes: hashed.to_json)
    codes # return plaintext for one-time display
  end

  def consume_backup_code!(code)
    codes = JSON.parse(otp_backup_codes || '[]')
    remaining = codes.reject do |hashed|
      ::BCrypt::Password.new(hashed) == code
    end
    update!(otp_backup_codes: remaining.to_json)
    remaining.size != codes.size # true if consumed
  end

  def backup_codes_remaining
    codes = JSON.parse(otp_backup_codes || '[]')
    codes.size
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
