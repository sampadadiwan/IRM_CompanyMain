# One attempt to change a user's existing mobile number, confirmed by a 6-digit code emailed
# to the user. Created by PhoneChangeStart, code sent by SendPhoneChangeCodeJob, consumed by
# PhoneChangeConfirm.
#
# The code is never stored — only an HMAC of it, keyed per request — so a database read
# cannot replay a pending change.
class PhoneChangeRequest < ApplicationRecord
  belongs_to :user
  belongs_to :requested_by, class_name: "User"

  # How long an emailed code stays usable.
  CODE_TTL = 10.minutes
  # Wrong guesses allowed before the request is cancelled. 5 of 1,000,000 codes.
  MAX_ATTEMPTS = 5
  # Minimum gap between two requests for the same user, and the hourly cap. Each request
  # sends an email, so these stop the button being used to flood a mailbox.
  RESEND_COOLDOWN = 1.minute
  HOURLY_LIMIT = 5

  # code_digest is not required: it stays nil until SendPhoneChangeCodeJob generates the code.
  validates :new_call_code, :new_phone, :expires_at, presence: true

  # Neither confirmed nor cancelled. Expiry is checked separately so the caller can say
  # "expired" rather than "no pending change".
  scope :pending, -> { where(verified_at: nil, cancelled_at: nil) }
  scope :since, ->(time) { where(created_at: time..) }

  # A fresh random 6-digit code, zero-padded.
  #
  # @return [String]
  def self.generate_code
    format("%06d", SecureRandom.random_number(1_000_000))
  end

  # Stores the digest of `code`. user and expires_at must already be set — both are part of
  # what the digest is bound to (see #digest_for).
  def code=(code)
    self.code_digest = digest_for(code)
  end

  # Constant-time check of a typed code against the stored digest.
  #
  # @param code [String]
  # @return [Boolean]
  def code_matches?(code)
    # Strip spaces a user may paste in ("123 456").
    typed = code.to_s.delete("^0-9")
    # No digest yet means the code email has not gone out, so nothing can match.
    return false if typed.length != 6 || code_digest.blank?

    ActiveSupport::SecurityUtils.secure_compare(digest_for(typed), code_digest.to_s)
  end

  def expired?
    expires_at <= Time.current
  end

  def attempts_left
    [MAX_ATTEMPTS - attempts, 0].max
  end

  # Call code + masked new number, e.g. "+91 xxxxxxx123" — same masking as
  # TwoFactorAuthenticatable#masked_phone_with_call_code.
  def masked_new_phone
    "+#{new_call_code} #{'x' * [new_phone.length - 3, 0].max}#{new_phone.last(3)}"
  end

  private

  # HMAC-SHA256 keyed by the app secret and bound to this user + expiry, so a digest copied
  # onto another request row does not verify there.
  def digest_for(code)
    key = Rails.application.key_generator.generate_key("phone_change_request")
    OpenSSL::HMAC.hexdigest("SHA256", key, "#{user_id}:#{expires_at.to_i}:#{code}")
  end
end
