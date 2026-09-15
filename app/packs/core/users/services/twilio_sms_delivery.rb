# Starts one Twilio Verify verification over SMS, and records the attempt.
#
# See docs/technical/twilio_sms_otp_design.md, sections 2 and 17.
#
# WHAT CHANGED FROM THE MESSAGES API (tag sms-messages-api-v1)
#
# We no longer generate, send or ever see the code. Twilio Verify mints it, delivers it
# from its own pre-registered sender pool, and holds it for ~10 minutes; we only ask for
# a verification to be started and later ask whether a code the user typed is the right
# one (TwilioSmsVerification).
#
# Three consequences worth knowing when reading this file:
#
#   * no message body, so no GSM-7 segment arithmetic and no template here — the wording
#     lives in the Verify service configuration in the Twilio console;
#   * no sender to configure, so no Messaging Service SID and no purchased number;
#   * the code is NOT the TOTP value any more, which is why the verification path has to
#     know which system issued the code the user is holding.
#
# Every guard still lives here rather than in the calling job so that a second caller
# cannot bypass them: the eligibility check, the rate limits and the delivery record are
# one unit. The job is only a queue entry point.
#
# Steps run in order and stop at the first failure (Trailblazer `step` semantics), which
# is exactly the ordering we want — never spend money before checking whether we should.
class TwilioSmsDelivery < Trailblazer::Operation
  # Raised instead of building a real Twilio client under RAILS_ENV=test — see .client.
  #
  # Deliberately inherits from Exception rather than StandardError: start_verification
  # rescues StandardError, so a StandardError here would be recorded as an ordinary
  # transport failure and the scenario would read as a flaky network rather than as the
  # missing @stub-twilio tag it is.
  class TestEnvironmentSendBlocked < Exception; end # rubocop:disable Lint/InheritException

  step :check_number_usable
  step :check_rate_limit
  step :start_verification
  step :record_success

  # The number must still be dialable and textable.
  #
  # Checked again here even though the mode-selection screen already called
  # sms_available?: a number can be edited between enrollment and any later login, and
  # SMS_OTP_ENABLED can be thrown at any time. There is no destination allowlist any
  # more — Twilio Geo Permissions is the only thing bounding where we dial (see
  # SmsDeliverable) — so this gate is about the number and the kill switch alone.
  def check_number_usable(ctx, user:, **)
    number = user.normalized_sms_number

    if number.blank?
      record_failure(ctx, user:, error_code: OtpDelivery::ERROR_INVALID_NUMBER)
      ctx[:error] = :invalid_number
      return false
    end

    # Full eligibility, not just number validity — this is the last gate before an API
    # call that costs money, so it must also honour the SMS_OTP_ENABLED kill switch.
    unless user.sms_otp_enabled?
      record_failure(ctx, user:, error_code: OtpDelivery::ERROR_NOT_ELIGIBLE)
      ctx[:error] = :not_eligible
      return false
    end

    ctx[:to_number] = number
    true
  end

  # Refuse rather than send when any window is exhausted.
  #
  # Verify has its own per-service rate limits and Fraud Guard, but they do not replace
  # this: theirs are per Verify service, ours are per destination number across the whole
  # estate, and a verification still costs money. A tripped limit is logged with the
  # scope that tripped it, because a per-number limit firing repeatedly for numbers
  # spread across unrelated tenants is the earliest available detection signal for toll
  # fraud. The user is never told which limit or when it resets; that would turn the
  # limiter into an oracle for probing the thresholds.
  def check_rate_limit(ctx, user:, **)
    result = OtpSmsRateLimiter.new(user).check_and_record
    return true if result.allowed?

    Rails.logger.warn "[TwilioSmsDelivery] rate limit hit user_id=#{user.id} scope=#{result.scope}"
    record_failure(ctx, user:, error_code: OtpDelivery::ERROR_RATE_LIMITED)
    ctx[:error] = :rate_limited
    false
  end

  def start_verification(ctx, user:, **)
    service_sid = self.class.verify_service_sid
    if service_sid.blank?
      # Misconfiguration, not a delivery failure — say so plainly rather than letting
      # Twilio return an opaque error on every single send.
      Rails.logger.error "[TwilioSmsDelivery] TWILIO_VERIFY_SERVICE_SID is not set. " \
                         "Create a Verify service in the Twilio console and store its " \
                         "VA… SID in credentials."
      record_failure(ctx, user:, error_code: "no_verify_service_configured")
      ctx[:error] = :no_verify_service_configured
      return false
    end

    Rails.logger.info "[TwilioSmsDelivery] BEGIN send user_id=#{user.id} " \
                      "to=***#{user.sms_number_last4} purpose=#{ctx[:purpose] || OtpDelivery::PURPOSE_LOGIN}"

    verification = twilio_client.verify.v2.services(service_sid)
                                .verifications.create(to: ctx[:to_number], channel: "sms")

    Rails.logger.info "[TwilioSmsDelivery] SUCCESS user_id=#{user.id} " \
                      "sid=#{verification.sid} status=#{verification.status}"

    ctx[:provider_message_id] = verification.sid
    true
  rescue Twilio::REST::RestError => e
    handle_twilio_error(ctx, user:, error: e)
    false
  rescue StandardError => e
    # Timeouts, connection resets and anything else below the REST layer raise
    # Twilio::REST::TwilioError or a Faraday error, NOT RestError. Left unrescued they
    # would escape the operation entirely: no OtpDelivery row, no ctx[:retryable], and
    # the job's structured failure log skipped.
    Rails.logger.error "[TwilioSmsDelivery] transport failure user_id=#{user.id} " \
                       "#{e.class}: #{e.message}"
    record_failure(ctx, user:, error_code: "transport_error")
    ctx[:error] = :transient_failure
    ctx[:retryable] = true
    # This attempt consumed the 60-second slot. Without giving it back, the retry
    # ActiveJob is about to schedule would be refused by our own limiter rather than
    # reaching Twilio — turning a recoverable blip into a failed login.
    OtpSmsRateLimiter.new(user).release_short_window
    false
  end

  def record_success(ctx, user:, **)
    ctx[:otp_delivery] = OtpDelivery.create!(
      user: user,
      channel: "sms",
      to_number_digest: user.sms_number_digest,
      to_number_last4: user.sms_number_last4,
      provider_message_id: ctx[:provider_message_id],
      status: OtpDelivery::STATUS_QUEUED,
      # No segments under Verify — Twilio owns the message body, so we cannot count them
      # and are not billed per segment anyway.
      segments: nil,
      purpose: ctx[:purpose] || OtpDelivery::PURPOSE_LOGIN
    )
    true
  end

  class << self
    # The Verify service ("VA…"), created in the Twilio console. Unlike the Messages API
    # this needs no purchased number and no A2P 10DLC brand/campaign registration of our
    # own — Verify sends from Twilio's managed, pre-registered pool.
    def verify_service_sid
      Rails.application.credentials[:TWILIO_VERIFY_SERVICE_SID].to_s.strip.presence
    end

    def account_sid
      Rails.application.credentials[:TWILIO_ACCOUNT_SID]
    end

    def auth_token
      Rails.application.credentials[:TWILIO_AUTH_TOKEN]
    end

    # Nothing in the test suite may reach the real Twilio API.
    #
    # The @stub-twilio hook replaces this whole method, so reaching the body of it under
    # RAILS_ENV=test means a scenario triggered a send without the tag. Today that call
    # would fail on the REPLACE_ME placeholders in config/credentials/test.yml.enc — but
    # the day someone pastes working credentials in to debug something, the same untagged
    # scenario sends a real message to a real handset. The two things that otherwise
    # prevent it are conventions rather than guarantees: SMS_OTP_ENABLED is simply absent
    # from .env.test, and WebMock is only switched on for @sync-http scenarios.
    def client
      if Rails.env.test?
        raise TestEnvironmentSendBlocked,
              "TwilioSmsDelivery.client was called in the test environment. Tag the " \
              "scenario @stub-twilio so the Twilio client is stubbed."
      end

      Twilio::REST::Client.new(account_sid, auth_token)
    end
  end

  private

  def twilio_client
    self.class.client
  end

  # Splits Twilio failures into "this will never work" and "try again".
  #
  # The permanent set is the important half. 60200 (invalid parameter — a malformed
  # destination) and 60605 (destination is a landline or otherwise unreachable) can never
  # succeed on retry, and retrying wastes a queue slot and an API call. 60203 means the
  # per-verification send limit is already exhausted, which a retry also cannot fix.
  def handle_twilio_error(ctx, user:, error:)
    permanent = OtpDelivery::TWILIO_PERMANENT_ERROR_CODES.include?(error.code)

    Rails.logger.error "[TwilioSmsDelivery] verification start failed user_id=#{user.id} " \
                       "code=#{error.code} permanent=#{permanent}"

    record_failure(ctx, user:, error_code: error.code.to_s)
    ctx[:error] = permanent ? :permanent_failure : :transient_failure
    ctx[:twilio_error_code] = error.code
    ctx[:retryable] = !permanent
  end

  # Failures are recorded as deliberately as successes: this table is the durable record
  # that shows an abuse pattern after the cache counters have expired, and "we refused to
  # send" is as much an answer to a support question as "we sent".
  def record_failure(ctx, user:, error_code:)
    ctx[:otp_delivery] = OtpDelivery.create!(
      user: user,
      channel: "sms",
      # Digest may be nil when the number could not be normalised at all; store a
      # sentinel so the NOT NULL column still records that an attempt happened.
      to_number_digest: user.sms_number_digest || "unparseable",
      to_number_last4: user.sms_number_last4,
      status: OtpDelivery::STATUS_FAILED,
      error_code: error_code.to_s,
      purpose: ctx[:purpose] || OtpDelivery::PURPOSE_LOGIN
    )
  end
end
