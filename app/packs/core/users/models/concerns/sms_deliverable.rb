# Turns the phone number we hold for a user into something Twilio will actually dial,
# and answers whether SMS two-factor is available to them at all.
#
# See docs/technical/twilio_sms_otp_design.md sections 4 and 7.
#
# Why eligibility is computed rather than stored in a column:
#
# WhatsApp needs `users.whatsapp_enabled` because being reachable on WhatsApp is a fact
# we cannot derive from our own data — the number has to be registered with WhatsApp,
# so a human has to assert it. SMS has no such precondition: a valid mobile number IS
# the entitlement. A stored boolean would only ever be a second, staler copy of a fact
# the phone number already carries, and when the copy goes stale the user cannot log in.
#
# So eligibility is computed, every time, from the number itself.
module SmsDeliverable
  extend ActiveSupport::Concern

  # Master switch for SMS two-factor, for every tenant at once.
  #
  # Deliberately environment rather than a per-entity permission flag: a single Twilio
  # account owned by CapHive carries all the traffic and absorbs all the cost, so there
  # is nothing a per-tenant toggle would express that this does not. It also means the
  # feature can be switched off everywhere in one step — which matters, because the
  # failure mode being guarded against is a runaway bill, and that is not a situation
  # where anyone wants to be flipping flags tenant by tenant.
  #
  # @return [Boolean]
  def self.feature_enabled?
    ENV.fetch("SMS_OTP_ENABLED", "false").to_s.strip.casecmp("true").zero?
  end

  # Destination countries we are permitted to text, as ISO 3166-1 alpha-2 codes.
  #
  # Derived from CURRENT_SITE — the per-country deployment marker that already exists
  # (.env.production.us sets US, .env.production.in sets IN) — rather than configured
  # separately. One source of truth means the two cannot drift apart.
  #
  # WHY A DESTINATION CHECK EXISTS AT ALL, given the deployment is already per-country:
  #
  # The deployment decides which market gets the feature. It does NOT constrain where a
  # message goes. A US deployment can hold users whose stored number is +91, +44 or +252,
  # and SMS pumping is priced by DESTINATION, not by which server sent it — an attacker's
  # payout comes from terminating traffic on an expensive route, and the US deployment
  # will happily dial one if nothing stops it. So the deployment answers "is this feature
  # on?" and this answers "may we dial that number?".
  #
  # This is the app-side half of a deliberately redundant pair. Twilio's own Geo
  # Permissions (set in their console, account-wide) are the backstop that holds even if
  # this code is wrong. This half exists to refuse at ENROLLMENT, on a screen where the
  # user can still pick another mode — rather than letting them enrol and then discover
  # at login that nothing arrives.
  #
  # @return [Array<String>]
  def self.allowed_countries
    case ENV.fetch("CURRENT_SITE", "").strip.upcase
    when "US" then %w[US]
    when "IN" then %w[IN]
    else
      # LOCAL/unset — development and test. Permissive so a developer can exercise the
      # flow with whatever number is in their seed data. Never reached in a deployed
      # environment, where CURRENT_SITE is always set.
      %w[US IN]
    end
  end

  # Region libphonenumber assumes when a number arrives with no country code of its own.
  # Taken from the allowlist rather than hardcoded to US for the same reason as above.
  #
  # @return [String]
  def self.default_region
    allowed_countries.first || "US"
  end

  # Can this user choose SMS as their two-factor mode?
  #
  # Called on every render of the mode-selection screen, so it must stay local — no
  # Twilio Lookup call belongs in here. Any network check happens once, at enrollment.
  #
  # @return [Boolean]
  def sms_available?
    parsed = parsed_phone
    return false if parsed.nil?
    return false unless parsed.valid?
    # Landlines cannot receive SMS. Catching this here means the user is told at mode
    # selection rather than after enrolling and then failing to log in.
    return false unless mobile_phone?(parsed)

    SmsDeliverable.allowed_countries.include?(parsed.country)
  end

  # The number in E.164 ("+14155550134"), which is the only format Twilio accepts.
  #
  # Note what this is fixing: `phone_with_call_code` concatenates call_code and phone
  # with no separator and no leading "+", producing exactly the format Twilio rejects.
  # Neither column has any format validation, so real data contains "(415) 555-0134",
  # "415-555-0134", leading trunk zeros, and numbers that already carry a "+".
  #
  # @return [String, nil] nil when the number cannot be dialled
  def normalized_sms_number
    parsed = parsed_phone
    return nil if parsed.nil? || !parsed.valid?

    parsed.e164
  end

  # Stable key for the number, used both as the per-number rate-limit key and as the
  # stored `otp_deliveries.to_number_digest`.
  #
  # Hashing the NORMALISED form is load-bearing, not a detail: if this hashed the raw
  # stored string then "(415) 555-0134" and "+14155550134" would be different keys, and
  # the per-number rate limit — the control that actually stops toll fraud — would be
  # defeated by re-saving the same number in a different format.
  #
  # @return [String, nil]
  def sms_number_digest
    number = normalized_sms_number
    return nil if number.blank?

    Digest::SHA256.hexdigest(number)
  end

  # Last few digits, for support to reference out loud. Same information the user
  # already sees via masked_phone_with_call_code, so nothing new is exposed.
  #
  # @return [String, nil]
  def sms_number_last4
    normalized_sms_number&.last(4)
  end

  private

  # Combines call_code and phone into something libphonenumber can parse.
  #
  # Handles the shapes that actually occur in the data: a call_code stored as "91" or
  # "+91", a phone that already carries its own country code, and punctuation anywhere.
  #
  # @return [Phonelib::Phone, nil] nil when there is nothing to parse
  def parsed_phone
    return nil if phone.blank?

    digits = phone.to_s.strip
    code   = call_code.to_s.strip.delete_prefix("+")

    # Prepend the call code only when the number is not already fully qualified —
    # doing it unconditionally turns "+14155550134" into "+1+14155550134". With no
    # call code stored there is nothing to prepend, so the number goes through as-is
    # and libphonenumber falls back to the deployment's region.
    candidate = digits.start_with?("+") || code.blank? ? digits : "+#{code}#{digits}"

    Phonelib.parse(candidate, SmsDeliverable.default_region)
  end

  # Phonelib reports a type per number; only mobile lines (and shared mobile/landline
  # ranges, which are common in the US where the type is genuinely ambiguous) can
  # receive SMS.
  #
  # @param parsed [Phonelib::Phone]
  # @return [Boolean]
  def mobile_phone?(parsed)
    types = Array(parsed.types)
    types.include?(:mobile) || types.include?(:fixed_or_mobile)
  end
end
