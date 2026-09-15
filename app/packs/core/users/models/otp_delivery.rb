# One attempt to deliver a two-factor one-time code over SMS.
#
# There are no inbound delivery receipts by design (see
# docs/technical/twilio_sms_otp_design.md), so a row here records what happened on the
# send call and nothing after it. `queued` means Twilio accepted the message, not that
# a handset received it.
class OtpDelivery < ApplicationRecord
  belongs_to :user

  # Accepted by Twilio. The furthest we ever get without delivery receipts.
  STATUS_QUEUED = "queued".freeze
  # Rejected by Twilio, or refused by us before we called them.
  STATUS_FAILED = "failed".freeze

  # Why we declined to send, for the cases Twilio never saw. Kept in the same column
  # as Twilio's numeric codes so a single field answers "why did this not go out?".
  ERROR_RATE_LIMITED        = "rate_limited".freeze
  ERROR_INVALID_NUMBER      = "invalid_number".freeze
  # SMS is switched off for the deployment, or the stored number is not textable
  # (a landline, most often). Replaces ERROR_UNSUPPORTED_COUNTRY, which named a
  # destination allowlist that no longer exists — see SmsDeliverable.
  ERROR_NOT_ELIGIBLE        = "not_eligible".freeze
  # Retained only so historical rows written before the allowlist was removed still
  # read back meaningfully. Nothing writes it any more.
  ERROR_UNSUPPORTED_COUNTRY = "unsupported_country".freeze

  # Twilio Verify errors that mean this attempt will never succeed on retry. Retrying
  # them wastes a queue slot and an API call — so these must not be re-raised for
  # ActiveJob to retry.
  #
  # These are Verify's codes, not the Messages API's (21211/21610/21612): under Verify
  # Twilio owns the sender, so the failures we see are about the destination and the
  # verification, not about our number or opt-out state on it.
  TWILIO_PERMANENT_ERROR_CODES = [
    60_200, # invalid parameter — malformed destination
    60_203, # max send attempts reached for this verification
    60_205, # SMS is not supported by this landline number
    60_605  # destination unreachable / blocked by Twilio geo permissions
  ].freeze

  validates :channel, :status, :purpose, :to_number_digest, presence: true

  # Enrollment failures are recoverable — the user is still on a screen where they can
  # choose another mode. Login failures lock them out. Worth telling apart when reading
  # this table during a support call.
  PURPOSE_ENROLLMENT = "enrollment".freeze
  PURPOSE_LOGIN      = "login".freeze

  scope :for_number, ->(digest) { where(to_number_digest: digest) }
  scope :since, ->(time) { where(created_at: time..) }

  # Counts sends to one number in a window. This is the query the per-number rate limit
  # falls back on, and the durable record that shows toll-fraud patterns the cache
  # counters cannot (they expire).
  #
  # Counts ATTEMPTS, not successes — a number that reliably errors must not become free
  # to hammer.
  #
  # @param digest [String] SHA-256 of the normalised E.164 number
  # @param window [ActiveSupport::Duration]
  # @return [Integer]
  def self.attempts_for_number(digest, window)
    for_number(digest).since(window.ago).count
  end

  def failed?
    status == STATUS_FAILED
  end
end
