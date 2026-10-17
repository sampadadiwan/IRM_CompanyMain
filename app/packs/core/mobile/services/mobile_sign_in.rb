# Turns an email + password (and, when two-factor is on, a code) into a phone session.
#
# Everything a website login checks is checked here, through the same machinery: Devise's
# valid_for_authentication? (which counts failed passwords toward the lockable lock), the
# active/deactivated check, and TwoFactorVerifier for the code. No phone session is ever issued
# to a two-factor user until a code has been verified — the challenge in between is a signed,
# 10-minute token that carries no session (lp-mobile-app H1, design card ②).
#
# The website keeps its challenge in the Rails session; the phone API is cookie-less, so the
# challenge state lives in a signed token plus two cache keys (attempts, spent).
class MobileSignIn
  CHALLENGE_TTL = 10.minutes
  CACHE_PREFIX = "mobile_2fa"

  Result = Struct.new(:kind, :device, :token, :challenge, :two_factor_method, :attempts_left, keyword_init: true) do
    def session? = kind == :session
  end

  class << self
    # @return [Result] kind ∈ :session, :challenge, :invalid, :locked, :not_investor,
    #   :finish_2fa_setup, :undeliverable
    def call(email:, password:, device:)
      user = User.find_for_authentication(email: email.to_s.strip.downcase)

      # X1 — same answer for an unknown email and a wrong password, so the phone API never
      # reveals whether an account exists (X14 wrong region looks exactly like this too)
      return Result.new(kind: :invalid) if user.nil?

      # X3 — an account already locked (by failed passwords here or on the website)
      return Result.new(kind: :locked) if user.access_locked?

      # valid_for_authentication? is what increments failed_attempts and locks the account,
      # exactly as a website login does
      unless ActiveRecord::Base.connected_to(role: :writing) { user.valid_for_authentication? { user.valid_password?(password.to_s) } }
        return Result.new(kind: user.reload.access_locked? ? :locked : :invalid)
      end
      return Result.new(kind: :invalid) unless user.active_for_authentication?

      # X4 — the app is for investors only
      return Result.new(kind: :not_investor) unless investor_persona?(user)

      # H2 — no two-factor: the session is issued straight away
      return session_for(user, device) unless user.two_factor_enabled?

      case (outcome = TwoFactorVerifier.start(user))
      when :choose_method then Result.new(kind: :finish_2fa_setup) # E4
      when :undeliverable then Result.new(kind: :undeliverable)
      else
        # H1 — a challenge, not a session
        challenge = issue_challenge(user, verify_sent: outcome == :sms_sent)
        # E3 — a code just went out, so the resend cooldown starts now (as on the website, where
        # the first send seeds otp_sms_sent_at)
        seed_resend_cooldown(read_challenge(challenge)["nonce"], user) if %i[sms_sent whatsapp_sent].include?(outcome)
        Result.new(kind: :challenge, challenge:, two_factor_method: user.two_factor_mode,
                   attempts_left: TwoFactorVerifier::MAX_ATTEMPTS)
      end
    end

    # @return [Result] kind ∈ :session, :invalid_code, :too_many_attempts, :expired, :spent
    def verify(challenge:, code:, device:)
      payload = read_challenge(challenge)
      # E2 — past its 10 minutes (or tampered)
      return Result.new(kind: :expired) if payload.nil?

      nonce = payload["nonce"]
      # A challenge already used for a session, or ended by too many wrong codes
      return Result.new(kind: :spent) if Rails.cache.read(cache_key(nonce, :spent))

      user = User.find_by(id: payload["user_id"])
      return Result.new(kind: :expired) if user.nil? || !user.active_for_authentication? || user.access_locked?

      if TwoFactorVerifier.verify(user, code, verify_code_sent: payload["verify_sent"])
        # Claim the challenge first: of two simultaneous correct submissions only one may mint
        # a session (double-tap)
        return Result.new(kind: :spent) unless claim(nonce)

        return session_for(user, device)
      end

      # E1 — wrong code: count it; X2 — the third ends the challenge, as on the website
      attempts = Rails.cache.increment(cache_key(nonce, :attempts), 1, expires_in: CHALLENGE_TTL).to_i
      if attempts >= TwoFactorVerifier::MAX_ATTEMPTS
        claim(nonce)
        Result.new(kind: :too_many_attempts)
      else
        Result.new(kind: :invalid_code, attempts_left: TwoFactorVerifier::MAX_ATTEMPTS - attempts)
      end
    end

    # E3 — resend an SMS / WhatsApp code for a live challenge, with the website's cooldown
    # @return [Symbol] :sent, :rate_limited, :not_needed, :expired, :undeliverable
    def resend(challenge:)
      payload = read_challenge(challenge)
      return :expired if payload.nil? || Rails.cache.read(cache_key(payload["nonce"], :spent))

      user = User.find_by(id: payload["user_id"])
      return :expired if user.nil?
      return :not_needed unless user.sms_mode? || user.whatsapp_mode?

      return :rate_limited unless seed_resend_cooldown(payload["nonce"], user)

      TwoFactorVerifier.start(user) == :undeliverable ? :undeliverable : :sent
    end

    # Investors, investor advisors and family-office users (who carry :investor) may use the app
    def investor_persona?(user)
      user.has_cached_role?(:investor) || user.has_cached_role?(:investor_advisor)
    end

    private

    def session_for(user, device)
      record, token = MobileDevice.register!(user, **device_attrs(device))
      Result.new(kind: :session, device: record, token:)
    end

    def device_attrs(device)
      device = device.to_h.symbolize_keys
      { install_id: device[:install_id], platform: device[:platform], name: device[:name],
        app_version: device[:app_version] }
    end

    # Starts the resend cooldown; false when one is already running. The window is the website's:
    # the SMS limiter's per-number window, 30 seconds for WhatsApp.
    def seed_resend_cooldown(nonce, user)
      window = user.sms_mode? ? OtpSmsRateLimiter.min_number_window : 30.seconds
      Rails.cache.write(cache_key(nonce, :resent), true, unless_exist: true, expires_in: window)
    end

    def verifier
      Rails.application.message_verifier(:mobile_2fa)
    end

    def issue_challenge(user, verify_sent:)
      verifier.generate({ "user_id" => user.id, "nonce" => SecureRandom.hex(16), "verify_sent" => verify_sent },
                        expires_in: CHALLENGE_TTL, purpose: :mobile_2fa)
    end

    def read_challenge(challenge)
      verifier.verified(challenge.to_s, purpose: :mobile_2fa)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
      nil
    end

    # true when THIS call ended the challenge. Fails closed on a cache error.
    def claim(nonce)
      Rails.cache.write(cache_key(nonce, :spent), true, unless_exist: true, expires_in: CHALLENGE_TTL + 1.minute) == true
    rescue StandardError => e
      Rails.logger.error("[mobile_2fa] claim failed: #{e.class}: #{e.message}")
      false
    end

    def cache_key(nonce, kind)
      "#{CACHE_PREFIX}:#{kind}:#{nonce}"
    end
  end
end
