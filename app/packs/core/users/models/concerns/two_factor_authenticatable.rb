module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  def whatsapp_mode?
    two_factor_mode == "whatsapp"
  end

  def authenticator_mode?
    two_factor_mode == "authenticator"
  end

  def generate_otp_secret
    self.otp_secret = User.generate_otp_secret
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
    hashed = codes.map { |c| BCrypt::Password.create(c) }
    update!(otp_backup_codes: hashed.to_json)
    codes # return plaintext for one-time display
  end

  def consume_backup_code!(code)
    codes = JSON.parse(otp_backup_codes || '[]')
    remaining = codes.reject do |hashed|
      BCrypt::Password.new(hashed) == code
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
