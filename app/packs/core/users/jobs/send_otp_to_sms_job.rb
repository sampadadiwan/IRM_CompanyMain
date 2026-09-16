# Delivers a two-factor one-time code by SMS.
#
# Mirrors SendOtpToWhatsappJob, with two deliberate differences:
#
# 1. No code crosses the queue at all. SendOtpToWhatsappJob passes the code as a job
#    argument, so a live credential is persisted in Redis and shown in the Sidekiq web
#    UI for the life of the job record. Under Verify the code is Twilio's and we never
#    hold it, so that exposure does not exist here.
#
# 2. It guards on derived eligibility rather than a stored flag — there is no per-user
#    opt-in column for SMS, because a valid mobile number is itself the entitlement.
#    See docs/modules/two_factor_auth/twilio_sms_otp_design.md.
class SendOtpToSmsJob < ApplicationJob
  # An OTP blocks a login, which makes it latency-critical in a way almost nothing else
  # in this system is. SendOtpToWhatsappJob sits on :default alongside bulk document and
  # report generation, where it can queue behind work that takes minutes. Verify's ~10
  # minute window is far more forgiving than the old 30-60 second TOTP one, but a user
  # staring at a code box has given up long before ten minutes.
  #
  # :critical is first in the server's queue list (config/initializers/sidekiq.rb) and
  # is otherwise unused, so an OTP is never behind anything. Must stay one of the queues
  # actually declared there — a job on an undeclared queue is enqueued and never run.
  queue_as :critical

  # @param user_id [Integer]
  # @param purpose [String] OtpDelivery::PURPOSE_ENROLLMENT or PURPOSE_LOGIN
  def perform(user_id, purpose = OtpDelivery::PURPOSE_LOGIN)
    user = User.find(user_id)

    # sms_otp_enabled?, not sms_available?: the second only asks whether the number is
    # textable. Checking it alone means the SMS_OTP_ENABLED kill switch — the documented
    # one-step stop for a runaway bill — would not actually stop anything, because every
    # already-enrolled user's login still reaches here.
    unless user.sms_otp_enabled?
      # Not an error worth raising: the switch may have been thrown, or the number edited
      # between enrollment and this send. Neither is something a retry would fix.
      Rails.logger.warn "[SendOtpToSmsJob] Aborting for user_id=#{user_id} " \
                        "(feature_enabled=#{SmsDeliverable.feature_enabled?}, " \
                        "number_usable=#{user.sms_available?})"
      return
    end

    # No code is passed or derived. Twilio Verify generates it, delivers it and holds it
    # for ~10 minutes; the application never sees it, which also means it can never leak
    # through a job argument into Redis or the Sidekiq web UI the way the WhatsApp job's
    # code does.
    result = ActiveRecord::Base.connected_to(role: :writing) do
      TwilioSmsDelivery.call(user: user, purpose: purpose)
    end

    return if result.success?

    # Deliberately never log the destination number — SendOtpToWhatsappJob logs it in
    # clear at info level on every send, which this does not copy. The OtpDelivery row
    # holds a digest and the last four digits, which is enough for support.
    Rails.logger.error "[SendOtpToSmsJob] Delivery failed user_id=#{user_id} " \
                       "reason=#{result[:error]}"

    # Only transient failures are re-raised. Retrying an invalid number or an opted-out
    # recipient can never succeed, costs a queue slot each time, and some carriers bill
    # rejected sends.
    raise "Twilio SMS delivery failed (#{result[:error]})" if result[:retryable]
  end
end
