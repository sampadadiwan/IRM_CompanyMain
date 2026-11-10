# The session-free core of a two-factor login challenge: send the code (for the out-of-band
# modes) and check what the user typed.
#
# WHY THIS EXISTS
#
# The website challenge lives in the Rails session (TwoFactorDispatch + Users::TwoFactorController)
# and the LP mobile app's challenge lives in a signed token (MobileSignIn), but both must apply
# the SAME rules — which modes send a code up front, when a mode is undeliverable, and which
# system (Twilio Verify or the TOTP secret) a typed code is checked against. Two copies of those
# rules would drift, and drift in 2FA is how a bypass or a lockout ships. So the rules live here
# once and both callers keep only their own state handling.
#
# openspec/changes/lp-mobile-app — design card ②, decision 4.
class TwoFactorVerifier
  # Code attempts per challenge before the user must sign in again — the website's rule
  # (lp-mobile-app X2).
  MAX_ATTEMPTS = 3

  # Twilio Verify holds a verification for ~10 minutes by default. Outside that window there is
  # nothing to check, so do not spend an API call finding out.
  VERIFY_CODE_TTL = 10.minutes

  # H13 — the website's per-challenge attempt count is kept server side as well as in the
  # cookie session, because a cookie saved before the misses can be replayed to reset the
  # session copy. Same lifetime as the phone app's challenge (MobileSignIn::CHALLENGE_TTL).
  WEB_CHALLENGE_TTL = 10.minutes
  WEB_CACHE_PREFIX = "web_2fa".freeze

  # H13 — wrong codes one user may enter, across every challenge on the website and the phone
  # app, in a rolling hour before the account is locked (Devise lock_access!, which also sends
  # the unlock email). Per-challenge limits alone cap guesses per password entry, not per hour.
  USER_MISS_LIMIT = 10
  USER_MISS_WINDOW = 1.hour
  # The rolling hour is summed from 10-minute buckets: each bucket is one atomic cache
  # increment, so two app servers counting the same user cannot lose a miss. Summing the
  # current bucket plus the six before it always covers at least the last full hour.
  USER_MISS_BUCKET = 10.minutes
  USER_MISS_PREFIX = "two_factor_misses".freeze

  # What a recorded wrong code amounts to.
  #   attempts — the challenge's server-side count (0 when the caller has no challenge id)
  #   locked   — this miss took the user to USER_MISS_LIMIT and the account is now locked
  Failure = Struct.new(:attempts, :locked, keyword_init: true)

  class << self
    # What the user typed, minus whitespace. Codes copied out of a WhatsApp or SMS message
    # routinely arrive as "123 456" or with a trailing space, and both the TOTP check and Twilio
    # Verify compare the exact string.
    def normalize(code)
      code.to_s.gsub(/\s+/, "")
    end

    # Starts a challenge for a user whose password has been accepted.
    #
    # @return [Symbol]
    #   :choose_method  two-factor is on but no method has been verified yet (lp-mobile-app E4)
    #   :undeliverable  WhatsApp / SMS mode, but no code can be sent — the caller must refuse
    #   :whatsapp_sent  a WhatsApp code is on its way
    #   :sms_sent       a Twilio Verify text is on its way
    #   :authenticator  nothing to send; the code comes from the user's app
    def start(user)
      # blank?, not nil?: an empty string (reachable through the cross-region sync, which assigns
      # the raw column) is "no method" too, and must not fall through to the authenticator branch.
      return :choose_method if user.two_factor_mode.blank?

      if user.whatsapp_mode?
        # SendOtpToWhatsappJob aborts silently when the flag or the number is gone, and a screen
        # saying "Code sent" for a code that never left is worse than a refusal.
        unless user.whatsapp_otp_enabled?
          Rails.logger.warn "[TwoFactorDispatch] whatsapp-mode user_id=#{user.id} cannot receive a " \
                            "code (whatsapp_enabled=#{user.whatsapp_enabled?}, phone_present=#{user.phone.present?})"
          return :undeliverable
        end

        # Out-of-band modes send the code up front so it is in flight while the code screen renders
        ActiveRecord::Base.connected_to(role: :writing) { user.send_otp_via_whatsapp }
        :whatsapp_sent
      elsif user.sms_mode?
        # Either the SMS_OTP_ENABLED kill switch was thrown or the number stopped being textable.
        # There are no backup codes, so refuse rather than show a code box nothing can satisfy.
        unless user.sms_otp_enabled?
          Rails.logger.warn "[TwoFactorDispatch] sms-mode user_id=#{user.id} cannot receive a " \
                            "code (feature_enabled=#{SmsDeliverable.feature_enabled?}, " \
                            "number_usable=#{user.sms_available?})"
          return :undeliverable
        end

        ActiveRecord::Base.connected_to(role: :writing) { user.send_otp_via_sms(OtpDelivery::PURPOSE_LOGIN) }
        :sms_sent
      else
        :authenticator
      end
    end

    # Does this code complete the challenge?
    #
    # Under Twilio Verify the typed code is not necessarily the TOTP value, so this has to know
    # which system issued it. Order is deliberate: Verify first (network, costs one of the
    # verification's limited attempts, so only when a Verify code is outstanding), then TOTP
    # (local and free). Probing Verify speculatively after a failed TOTP entry would burn a user's
    # real attempts on codes that were never Verify codes.
    #
    # @param verify_code_sent [Boolean] the caller's own hint that it sent a Verify code
    def verify(user, code, verify_code_sent: false)
      code = normalize(code)
      return false if code.blank?

      (verify_code_pending?(user, verify_code_sent:) && TwilioSmsVerification.approved?(user:, code:)) ||
        user.validate_and_consume_otp!(code)
    end

    # Should the typed code be checked against Twilio Verify?
    #
    # Answered from DURABLE state, not from the caller's hint alone — a correct code was once
    # rejected because the hint was missing while the challenge was present. In order of certainty:
    #   1. sms_mode? — these users never saw a QR code, so their code is always Twilio's;
    #   2. the caller's hint that it just sent one;
    #   3. a queued SMS delivery inside the Verify code's lifetime — covers the authenticator user
    #      who pressed "Text me a code".
    # An authenticator user who never requested a text matches none of these, so Verify is never
    # probed speculatively.
    def verify_code_pending?(user, verify_code_sent: false)
      return true if user.sms_mode?
      return true if verify_code_sent

      OtpDelivery.where(user_id: user.id, channel: "sms", status: OtpDelivery::STATUS_QUEUED)
                 .exists?(created_at: VERIFY_CODE_TTL.ago..)
    end

    # Counts one wrong website code: against its challenge (when the caller has a challenge id)
    # and against the user's rolling hour.
    #
    # Under the test env's :null_store the increment returns nil, so attempts reads 0 and the
    # caller's own session count decides — exactly today's behaviour (H13 fix 1).
    #
    # @param challenge_id [String, nil] session[:otp_challenge_id], set by TwoFactorDispatch
    # @return [Failure]
    def record_failure(user, challenge_id:)
      # M12 (OWASP 2026-11): wrong 2FA codes are counted, so guessing raises an alert
      SecurityMetrics.event(:two_factor_failed, reason: "code")
      # The challenge's own count; nil from a store that keeps nothing reads as 0
      attempts = if challenge_id.present?
                   Rails.cache.increment(web_challenge_key(challenge_id), 1, expires_in: WEB_CHALLENGE_TTL).to_i
                 else
                   0
                 end
      # H13-2 — the same miss also counts toward the per-user hourly lockout
      Failure.new(attempts:, locked: record_user_miss(user))
    end

    # The challenge's server-side count without adding to it — read before a code is checked,
    # so a replayed cookie whose challenge is already spent cannot get one more guess in.
    # @return [Integer]
    def challenge_attempts(challenge_id)
      return 0 if challenge_id.blank?

      Rails.cache.read(web_challenge_key(challenge_id)).to_i
    end

    # Counts one wrong code toward the user's rolling-hour limit (website and phone app alike)
    # and locks the account when it reaches USER_MISS_LIMIT.
    #
    # The buckets are deliberately NOT cleared on lock: a miss after an unlock (Devise unlocks by
    # email, or by time after config.unlock_in) inside the same hour is still over the limit and
    # locks again, which is what "10 per rolling hour" means.
    #
    # @return [Boolean] true when this miss locked the account
    def record_user_miss(user)
      now_bucket = Time.current.to_i / USER_MISS_BUCKET.to_i
      # This miss lands in the current bucket; kept long enough to still be summed an hour later
      Rails.cache.increment(user_miss_key(user, now_bucket), 1, expires_in: USER_MISS_WINDOW + (2 * USER_MISS_BUCKET))

      # The rolling hour: the current bucket and the six before it, in one read
      bucket_count = (USER_MISS_WINDOW / USER_MISS_BUCKET).to_i
      keys = (0..bucket_count).map { |back| user_miss_key(user, now_bucket - back) }
      misses = Rails.cache.read_multi(*keys).values.sum(&:to_i)
      return false if misses < USER_MISS_LIMIT

      # At the limit: lock (Devise sends the unlock email when the email unlock strategy is on).
      # A user already locked is left alone, so a burst of misses sends one email, not ten.
      ActiveRecord::Base.connected_to(role: :writing) do
        user.reload
        next false if user.access_locked?

        Rails.logger.warn("[two_factor] user_id=#{user.id} locked after #{misses} wrong codes in #{USER_MISS_WINDOW.inspect}")
        user.lock_access!
        true
      end
    end

    private

    def web_challenge_key(challenge_id)
      "#{WEB_CACHE_PREFIX}:#{challenge_id}"
    end

    def user_miss_key(user, bucket)
      "#{USER_MISS_PREFIX}:#{user.id}:#{bucket}"
    end
  end
end
