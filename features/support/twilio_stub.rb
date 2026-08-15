# Support for @stub-twilio scenarios, which exercise the SMS two-factor flow.
#
# Deliberately stubs at the HTTP boundary only, NOT at the job like @stub-whatsapp does.
# Stubbing SendOtpToSmsJob would skip everything worth testing — the country allowlist,
# the rate limiters and the OtpDelivery bookkeeping all live inside TwilioSmsDelivery,
# and those are precisely the parts that stand between the send endpoint and a runaway
# bill. So the real operation runs and only the Twilio API calls are faked.
#
# TWILIO VERIFY CHANGES WHO OWNS THE CODE
#
# Under the old Messages API the code was the user's own TOTP value, so a step could read
# it straight off the record with `current_otp`. Under Verify, Twilio mints and holds the
# code and the application never sees it — so this stub mints one, hands it out through
# `@twilio.last_code`, and answers the verification check by comparing against it. That
# is the same contract the real service has: we send a request, and later ask Twilio
# whether what the user typed matches.
#
# The test environment neuters two things this feature depends on:
#   * config.cache_store is :null_store, so the rate-limit counters would silently never
#     persist — this hook swaps in a real store, as @rack_attack does;
#   * SMS_OTP_ENABLED / CURRENT_SITE come from the deployment's env file, which the test
#     env does not set.
# Both are restored afterwards so no other feature is affected.

# Stands in for a Verify service: records verifications started, and adjudicates checks.
class TwilioStubRecorder
  Sent = Struct.new(:to, :code, :sid, keyword_init: true)

  def initialize
    @sent = []
    @next_error = nil
    @checks = 0
  end

  attr_reader :sent, :checks

  # Makes the NEXT verification start raise the given Twilio error, for failure paths.
  def fail_next_with(code, message = "stubbed Twilio failure")
    @next_error = [code, message]
  end

  # Mirrors verifications.create — starts a verification and mints the code Twilio would
  # have texted.
  def start_verification(to:)
    if (err = @next_error)
      @next_error = nil
      raise Twilio::REST::RestError.new(err[1], FakeTwilioResponse.new(err[0], err[1]))
    end

    code = format("%06d", SecureRandom.random_number(1_000_000))
    sent = Sent.new(to: to, code: code, sid: "VE#{SecureRandom.hex(16)}")
    @sent << sent
    FakeTwilioVerification.new(sent.sid, "pending")
  end

  # Mirrors verification_checks.create. Counting calls matters: a real verification allows
  # only a few checks before it is consumed, which is why the controller must never probe
  # Verify speculatively — a scenario can assert on this.
  def check(to:, code:)
    @checks += 1
    match = @sent.reverse.find { |s| s.to == to }
    approved = match.present? && match.code == code.to_s
    FakeTwilioVerification.new(match&.sid || "VE#{SecureRandom.hex(16)}",
                               approved ? "approved" : "pending")
  end

  def last = @sent.last
  def count = @sent.size
  # The code the user would have received. Under Verify this only exists because the
  # stub minted it — the application has no way to know it.
  def last_code = last&.code
end

FakeTwilioVerification = Struct.new(:sid, :status)

# Twilio::REST::RestError reads code/message off the response object it is given.
class FakeTwilioResponse
  attr_reader :status_code, :body

  def initialize(code, message)
    @status_code = 400
    @body = { "code" => code, "message" => message, "status" => 400 }
  end

  def error_code = body["code"]
end

# Minimal stand-in for client.verify.v2.services(sid), exposing the two collections the
# application uses.
class FakeVerifyService
  def initialize(recorder)
    @recorder = recorder
  end

  def verifications
    recorder = @recorder
    @verifications ||= Object.new.tap do |o|
      o.define_singleton_method(:create) { |to:, channel:| recorder.start_verification(to: to) }
    end
  end

  def verification_checks
    recorder = @recorder
    @verification_checks ||= Object.new.tap do |o|
      o.define_singleton_method(:create) { |to:, code:| recorder.check(to: to, code: code) }
    end
  end
end

Before('@stub-twilio') do
  @twilio = TwilioStubRecorder.new

  @twilio_original_cache = Rails.cache
  # Fresh in-memory store per scenario: the per-number and per-user counters behave
  # like production (including expiry) and cannot leak between scenarios.
  Rails.cache = ActiveSupport::Cache::MemoryStore.new

  @twilio_original_env = ENV.to_h.slice("SMS_OTP_ENABLED", "CURRENT_SITE")
  ENV["SMS_OTP_ENABLED"] = "true"
  # LOCAL allows both US and IN destinations, so scenarios can use either.
  ENV["CURRENT_SITE"] = "LOCAL"

  # A well-formed Verify service SID. Not read from credentials — the test environment
  # holds a placeholder, and a scenario should not depend on whether someone filled it in.
  allow(TwilioSmsDelivery).to receive(:verify_service_sid).and_return("VA#{'0' * 32}")

  service = FakeVerifyService.new(@twilio)
  fake_v2 = Object.new
  fake_v2.define_singleton_method(:services) { |_sid| service }
  fake_verify = Object.new
  fake_verify.define_singleton_method(:v2) { fake_v2 }
  fake_client = Object.new
  fake_client.define_singleton_method(:verify) { fake_verify }

  allow(TwilioSmsDelivery).to receive(:client).and_return(fake_client)
end

After('@stub-twilio') do
  Rails.cache = @twilio_original_cache if @twilio_original_cache
  %w[SMS_OTP_ENABLED CURRENT_SITE].each do |k|
    if @twilio_original_env&.key?(k)
      ENV[k] = @twilio_original_env[k]
    else
      ENV.delete(k)
    end
  end
end
