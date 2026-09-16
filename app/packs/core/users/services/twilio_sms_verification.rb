# Checks a code the user typed against Twilio Verify.
#
# See docs/modules/two_factor_auth/twilio_sms_otp_design.md section 17.
#
# This has no equivalent under the Messages API, where the code WAS the rolling TOTP
# value and `validate_and_consume_otp!` could answer locally. Under Verify the code is
# Twilio's, so answering "is this right?" is a network call.
#
# Two things about that which matter to callers:
#
#   * It costs an attempt. A verification allows a limited number of checks (5 by
#     default) before it is consumed, so this must only be called when a Verify code was
#     actually issued — never as a speculative "maybe it's a Verify code" probe after a
#     failed TOTP check. Users::TwoFactorController tracks the issuing channel in the
#     session for exactly this reason.
#   * A missing verification is not an error. Twilio returns 404 when there is no pending
#     verification for that number — expired, already approved, or never started. That is
#     a plain "no", not an exception the caller should have to rescue.
class TwilioSmsVerification < Trailblazer::Operation
  step :check_configured
  step :check_code

  # Twilio returns 404 when no verification is pending for this number. Reached by simply
  # waiting past the ~10 minute window, so it is an ordinary outcome rather than a fault.
  NOT_FOUND_ERROR_CODE = 20_404

  def check_configured(ctx, user:, **)
    number = user.normalized_sms_number
    if number.blank? || TwilioSmsDelivery.verify_service_sid.blank?
      # Not a wrong code — we were never in a position to ask. Without this line the user
      # sees "invalid code" and the log shows nothing at all.
      Rails.logger.error "[TwilioSmsVerification] FAIL user_id=#{user.id} reason=not_configured " \
                         "(number_usable=#{number.present?}, " \
                         "verify_service_set=#{TwilioSmsDelivery.verify_service_sid.present?})"
      ctx[:approved] = false
      return false
    end

    ctx[:to_number] = number
    true
  end

  # Logged at every outcome, because this is the call that decides whether someone gets
  # into the account and it is the hardest thing in the flow to diagnose after the fact:
  # it happens on Twilio's side, and a rejection looks identical to a wrong code, an
  # expired verification and a network fault unless we say which it was.
  #
  # The code itself is NEVER logged — it is a live credential for its whole lifetime.
  # The destination is logged as its last 4 digits only, matching what the OtpDelivery
  # row stores and what support can already say out loud.
  def check_code(ctx, user:, code:, **)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Rails.logger.info "[TwilioSmsVerification] BEGIN check user_id=#{user.id} " \
                      "to=***#{user.sms_number_last4}"

    check = TwilioSmsDelivery.client
                             .verify.v2.services(TwilioSmsDelivery.verify_service_sid)
                             .verification_checks.create(to: ctx[:to_number], code: code.to_s)

    # "approved" is the only success. "pending" means the code was wrong and the
    # verification is still open for further attempts.
    ctx[:approved] = check.status == "approved"

    if ctx[:approved]
      Rails.logger.info "[TwilioSmsVerification] SUCCESS user_id=#{user.id} " \
                        "sid=#{check.sid} #{elapsed(started)}"
    else
      # Twilio reports a wrong code as status=pending rather than as an error, so without
      # this line a mistyped code leaves no trace at all.
      Rails.logger.warn "[TwilioSmsVerification] FAIL user_id=#{user.id} reason=code_mismatch " \
                        "status=#{check.status} sid=#{check.sid} #{elapsed(started)}"
    end

    ctx[:approved]
  rescue Twilio::REST::RestError => e
    if e.code == NOT_FOUND_ERROR_CODE
      # Reached by simply waiting past the ~10 minute window, or by checking twice after
      # an approval. Ordinary, so info rather than error — but still worth a line,
      # because "I typed it right" and "I typed it too late" look the same to the user.
      Rails.logger.info "[TwilioSmsVerification] FAIL user_id=#{user.id} reason=no_pending_verification " \
                        "(expired, already used, or never started) #{elapsed(started)}"
    else
      Rails.logger.error "[TwilioSmsVerification] FAIL user_id=#{user.id} reason=twilio_error " \
                         "code=#{e.code} #{elapsed(started)}"
    end
    ctx[:approved] = false
    false
  rescue StandardError => e
    # A transport failure must not be read as "wrong code" by anything that logs or
    # counts attempts differently, but from the user's point of view the only honest
    # answer is that we could not verify it. Fails closed.
    Rails.logger.error "[TwilioSmsVerification] FAIL user_id=#{user.id} reason=transport " \
                       "#{e.class}: #{e.message} #{elapsed(started)}"
    ctx[:approved] = false
    false
  end

  # Convenience wrapper: callers only ever want the boolean.
  #
  # @param user [User]
  # @param code [String] what the user typed
  # @return [Boolean] true only when Twilio approved the code
  def self.approved?(user:, code:)
    return false if code.blank?

    call(user: user, code: code)[:approved] == true
  end

  private

  def elapsed(started)
    "duration_ms=#{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round}"
  end
end
