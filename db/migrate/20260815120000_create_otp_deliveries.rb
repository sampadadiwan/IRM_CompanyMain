# Records every attempt to deliver a two-factor one-time code over SMS.
# See docs/modules/two_factor_auth/twilio_sms_otp_design.md.
#
# Why a dedicated table rather than reusing WhatsappLog: WhatsappLog belongs_to
# :notification and :entity, and an OTP send has neither. The user is signed out at
# that point (Users::TwoFactorController holds only an id in the session) and no
# Notification record is involved.
#
# Two jobs, and both matter:
#
# 1. Support answers. "I never got the code" is unanswerable without a record of
#    whether we sent, when, and to which number. There are no inbound delivery
#    receipts by design, so the send call is the only thing we ever learn.
#
# 2. Abuse detection. SMS costs real money per message and is the standard target
#    for toll fraud (an attacker drives sends to premium-rate numbers they control
#    and takes a cut). The per-number rate limits live in the cache for speed, but
#    this table is the durable record that shows the pattern after the fact.
class CreateOtpDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :otp_deliveries do |t|
      t.references :user, null: false, foreign_key: true

      # 'sms' today. Widened only if the WhatsApp path is ever brought under the
      # same recording, which is why this is not a boolean.
      t.string :channel, null: false, default: "sms"

      # SHA-256 of the normalised E.164 number, never the number itself.
      #
      # This table is read by support staff, so a plaintext phone column keyed by
      # user would be a standing privacy liability for no operational gain — a
      # digest answers "did we send to the number on file?" just as well, because
      # the comparison is always against a number we can re-derive and re-hash.
      #
      # Normalisation happens BEFORE hashing: "+14155550134" and "(415) 555-0134"
      # must produce one digest, or the per-number rate limit is defeated by
      # re-saving the same number in a different format.
      t.string :to_number_digest, null: false, limit: 64

      # Last 4 digits in clear, so support can say "ending 0134" out loud without
      # reversing the digest. One more digit than masked_phone_with_call_code shows on
      # screen, which is a deliberate trade for support usefulness — still far short of
      # identifying a number.
      t.string :to_number_last4, limit: 4

      # Twilio's MessageSid. Lets support look a specific message up in Twilio's
      # console or API on demand — a rare, manual lookup. Null when the send was
      # rejected before Twilio issued one.
      t.string :provider_message_id

      # Only two values exist. There are no inbound status callbacks, so we never
      # learn 'delivered' or 'undelivered':
      #   queued — Twilio accepted the message
      #   failed — the send call was rejected, or we refused to make it
      t.string :status, null: false

      # Twilio error code (21211 invalid number, 21610 opted out, 21612 unreachable
      # route), or one of our own reasons when we declined to send at all
      # (rate_limited, unsupported_country, invalid_number).
      t.string :error_code

      # Segment count, computed locally from the message body. A code that tips a
      # message into two segments silently doubles the bill, so it is recorded to
      # make that visible rather than discovered on an invoice.
      t.integer :segments

      # 'enrollment' or 'login'. An enrollment failure is recoverable (the user can
      # still pick another mode); a login failure locks them out. Worth telling apart.
      t.string :purpose, null: false

      t.timestamps
    end

    # The per-number abuse query: "how many sends to this number in the last N?".
    # The 30-day window is the one that catches slow, patient toll fraud that stays
    # under every shorter limit, so this index carries the longest scan.
    add_index :otp_deliveries, %i[to_number_digest created_at]

    # The per-user cap, and the support lookup ("what did we send this user?").
    add_index :otp_deliveries, %i[user_id created_at]

    # Support looking up one specific Twilio message.
    add_index :otp_deliveries, :provider_message_id
  end
end
