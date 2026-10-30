# Turns what Digio's signing panel reports into one of a fixed set of plain-language messages, so a
# signer never sees a raw Digio code and the wording lives in one place.
#
# Codes come from public/digio docs/error codes.txt. Digio spells one code two ways
# (DOCUEMNT_NOT_READY_FOR_THIS_ACTION in its documentation), so both map to the same group.
# A code not listed is treated as a problem on our side.
#
# Worked examples X1-X9 — openspec/changes/embedded-esign-digio/design.md#worked-examples
module DigioSdkErrors
  # message: what the signer reads. action: "retry" (offer Try again), "none", or "done".
  # check: ask Digio for the real status. alert: tell support.
  Result = Struct.new(:group, :message, :action, :check, :alert, keyword_init: true)

  # Wording for states the signing page itself reports, kept with the rest so it is in one place
  NOT_AVAILABLE_MESSAGE = "This signature request is not available for your account.".freeze
  CLOSED_MESSAGE = "This document is no longer waiting for signatures.".freeze
  ALREADY_SIGNED_MESSAGE = "You have already signed this document.".freeze
  NOT_YOUR_TURN_MESSAGE = "It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed.".freeze
  COMPLETED_MESSAGE = "Thank you. Your signature has been submitted and is being confirmed.".freeze
  CANCELLED_MESSAGE = "Signing was cancelled. You can start again whenever you are ready.".freeze
  PANEL_UNAVAILABLE_MESSAGE = "We couldn't load the signing panel. Please check your connection and try again, " \
                              "or use the link in the email from Digio.".freeze
  OURS_MESSAGE = "Something went wrong on our side and the team has been notified. " \
                 "Please try again later or contact support.".freeze

  GROUPS = {
    retry: Result.new(group: :retry, message: "Signing didn't go through. Please check your details and try again.",
                      action: "retry", check: false, alert: false),
    unavailable: Result.new(group: :unavailable, message: "The signing service is temporarily unavailable. Please try again in a little while.",
                            action: "retry", check: false, alert: false),
    aadhaar: Result.new(group: :aadhaar,
                        message: "Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method.",
                        action: "none", check: false, alert: false),
    cancelled: Result.new(group: :cancelled, message: CANCELLED_MESSAGE, action: "retry", check: false, alert: false),
    already_signed: Result.new(group: :already_signed, message: ALREADY_SIGNED_MESSAGE, action: "none", check: true, alert: false),
    in_progress: Result.new(group: :in_progress,
                            message: "A signing request is already in progress. Please wait a moment and check the status again.",
                            action: "none", check: true, alert: false),
    expired: Result.new(group: :expired, message: "This signing request has expired. Please ask the sender to send it again.",
                        action: "none", check: false, alert: false),
    method_changed: Result.new(group: :method_changed,
                               message: "The signing method for this document has changed. Please ask the sender to send it again.",
                               action: "none", check: false, alert: false),
    not_ready: Result.new(group: :not_ready, message: "This document isn't ready to be signed yet. Please try again in a few minutes.",
                          action: "retry", check: false, alert: false),
    turn: Result.new(group: :turn, message: NOT_YOUR_TURN_MESSAGE, action: "none", check: false, alert: false),
    ours: Result.new(group: :ours, message: OURS_MESSAGE, action: "none", check: false, alert: true)
  }.freeze

  CODES = {
    # The signer closed the panel (X), before or after the code was sent: not an error, nobody is alerted
    "CANCELLED" => :cancelled,
    # The signer can fix it and try again
    "OTP_INVALID" => :retry, "AUTHENTICATION_FAILED" => :retry, "BIOMETRIC_DATA_MISMATCH" => :retry,
    "BIOMETRIC_LOCKED" => :retry, "INCORRECT_AADHAAR_ID" => :retry, "INVALID_ELECTRONIC_SIGNATURE" => :retry,
    "SIGNING_TIMED_OUT_ON_ESP" => :retry, "SIGNING_CANCELLED_ON_ESP" => :retry,
    # Digio / UIDAI is down: try later
    "ERROR_FROM_ESP_UIDAI" => :unavailable, "ESP_UIDAI_DOWN" => :unavailable,
    "AADHAAR_ESIGN_TEMPORARILY_UNAVAILABLE" => :unavailable, "ESIGN_REQUEST_FAILURE" => :unavailable,
    # The signer's Aadhaar cannot be used
    "AADHAAR_HAS_NO_MOBILE" => :aadhaar, "AADHAAR_HAS_NO_MOBILE_OR_EMAIL" => :aadhaar, "AADHAAR_SUSPENDED" => :aadhaar,
    "AADHAAR_NOT_AUTHENTICABLE" => :aadhaar, "AADHAAR_CANCELLED" => :aadhaar,
    # Our state is behind Digio's: ask Digio
    "ALREADY_SIGNED" => :already_signed, "DUPLICATE_REQUEST" => :in_progress,
    # The sender has to act
    "SIGN_REQUEST_EXPIRED" => :expired, "REQUESTED_SIGN_METHOD_DIFFERENT" => :method_changed,
    # Not ready yet; both spellings Digio uses
    "DOCUMENT_NOT_READY_FOR_THIS_ACTION" => :not_ready, "DOCUEMNT_NOT_READY_FOR_THIS_ACTION" => :not_ready,
    # Not this signer's turn
    "SIGNING_NOT_ALLOWED" => :turn,
    # Not the signer's problem
    "NOT_SUFFICIENT_ENTITLEMENTS" => :ours, "INVALID_SIGNER" => :ours, "UNAUTHORIZED_ACCESS" => :ours,
    "SYSTEM_ERROR" => :ours, "UNKNOWN_ERROR" => :ours
  }.freeze

  COMPLETED_EVENTS = %w[sign.completed sign.electronic.completed sign.aadhaar.completed sign.dsc.completed].freeze

  CLIENT_EVENTS = {
    "client.cancelled" => GROUPS.fetch(:cancelled),
    "client.panel_unavailable" => Result.new(group: :panel_unavailable, message: PANEL_UNAVAILABLE_MESSAGE,
                                             action: "retry", check: false, alert: false)
  }.freeze

  COMPLETION = Result.new(group: :completed, message: COMPLETED_MESSAGE, action: "done", check: true, alert: false)

  module_function

  # @param code [String, nil] a Digio error code
  # @return [Result] unknown or blank codes are treated as a problem on our side
  def lookup(code)
    GROUPS.fetch(CODES.fetch(code.to_s.strip.upcase, :ours))
  end

  # @param event [String, nil] an SDK event name such as "sign.aadhaar.completed"
  def completed?(event)
    COMPLETED_EVENTS.include?(event.to_s.strip.downcase)
  end

  # @return [Result] the result for a completed signature
  def completion
    COMPLETION
  end

  # @param name [String] "client.cancelled" or "client.panel_unavailable"
  # @return [Result, nil]
  def client_event(name)
    CLIENT_EVENTS[name.to_s]
  end
end
