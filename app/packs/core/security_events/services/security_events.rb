# frozen_string_literal: true

# The one call every security event hook makes (OWASP review 2026-11 M11, design card ③).
#
#   SecurityEvents.record("role.granted", user: grantee, details: { role: "approver" })
#
# It builds the event on the request thread from memory only (IP, user agent, request id, actor, impersonator,
# firm, a fresh uid, the time) and hands it to SecurityEventWriteJob once every open transaction has committed —
# so a role granted inside a transaction that rolls back records nothing (E24).
#
# Recording must never change or fail the action that triggered it (design D5, Requirement "Recording never
# affects the user"). Three tiers:
#   1. enqueue SecurityEventWriteJob                      (normal path, H28)
#   2. the queue raised → insert inline on the primary    (E34 — e.g. Redis MISCONF when the data disk fills)
#   3. that raised too → one `[security_event]` warn line with kind, user id, firm, IP and time (X3)
# and a top-level rescue around the whole build, so an unknown kind (E35) or any bug here is logged, not raised.
#
# Alongside, it publishes ActiveSupport::Notifications "recorded.security_event" (kind, outcome, door — no
# personal data) so SecurityMetrics (M12) may count from it later instead of adding a second hook.
module SecurityEvents
  NOTIFICATION = "recorded.security_event"
  # X3 — at most one exception email per this window when inline writes keep failing
  NOTIFY_EVERY = 10.minutes

  module_function

  # @param kind [String] a SecurityEventCatalogue kind
  # @param user [User, nil] the account the event is about
  # @param door [String, Symbol, nil] how they came in; defaults from the request (SecurityEventContext.default_door)
  # @param outcome [Symbol] :success or :failure
  # @param details [Hash] kind-specific, sliced to the Catalogue allowlist (E36)
  # @param entity_id [Integer, nil] the firm, when the hook knows it better than the account / actor do
  # @param email [String, nil] the typed email on a failure with no known account: stored only as a digest;
  #   the job also tries to resolve it to an account (S2a)
  # @param actor [User, nil, :current] Done by; :current reads it from the request / job
  # @param request [ActionDispatch::Request, nil] for hooks that run outside a controller action
  # @return [nil] always
  def record(kind, user: nil, door: nil, outcome: :success, details: {}, entity_id: nil, email: nil, actor: :current, request: nil)
    attrs = build(kind, user:, door:, outcome:, details:, entity_id:, email:, actor:, request:)
    # M12 may count from this later; kind / outcome / door only
    ActiveSupport::Notifications.instrument(NOTIFICATION, kind: attrs["kind"], outcome: attrs["outcome"], door: attrs["door"])
    # E24 — after the outer transaction commits; at once when none is open
    ActiveRecord.after_all_transactions_commit { deliver(attrs) }
    nil
  rescue StandardError => e
    # E35 / E49 — an unknown kind or a bug in building the event: log it, never fail the action
    log("record_failed", kind:, user_id: user.try(:id), error: e)
    nil
  end

  # Builds the plain attrs hash (string keys, primitives only — it travels through Sidekiq)
  def build(kind, user:, door:, outcome:, details:, entity_id:, email:, actor:, request:)
    # E35 — KeyError for a kind that is not in the catalogue
    spec = SecurityEventCatalogue.fetch(kind)
    ctx = SecurityEventContext.current(request:)
    # Done by: the request's / job's user unless the hook names one (Login as names the support user)
    actor_user = actor == :current ? ctx[:actor] : actor
    attrs = {
      "uid" => SecureRandom.uuid,
      "kind" => kind.to_s,
      "category" => spec[:category],
      "outcome" => outcome.to_s == "failure" ? "failure" : "success",
      "door" => (door.presence || ctx[:door]).to_s,
      "user_id" => user&.id,
      "actor_id" => actor_user&.id,
      "impersonator_id" => ctx[:impersonator_id],
      # The firm the hook names (a firm deactivation, a firm dump), else the account's, else the actor's;
      # nil = CapHive only (D7)
      "entity_id" => entity_id || user&.entity_id || actor_user&.entity_id,
      "ip_address" => ctx[:ip_address],
      "user_agent" => ctx[:user_agent],
      "request_id" => ctx[:request_id],
      "region" => region,
      "details" => SecurityEventCatalogue.slice_details(kind, details),
      # Set here, not in the job: writes are asynchronous, so created_at is only the write time
      "occurred_at" => Time.current.utc.iso8601(6)
    }
    # D10 — an unknown account keeps only the digest; the job may still resolve the email to a user (S2a)
    if user.nil? && email.present?
      attrs["identifier_digest"] = SecurityEventContext.identifier_digest(email)
      attrs["email"] = email.to_s.strip.downcase
    end
    attrs
  end

  # Tier 1 → 2 → 3. Runs after commit, so it rescues everything itself: an error here would surface in the
  # caller's commit.
  def deliver(attrs)
    SecurityEventWriteJob.perform_later(attrs)
  rescue StandardError => e
    # E34 — the queue is down: write inline instead
    log("enqueue_failed", kind: attrs["kind"], user_id: attrs["user_id"], error: e)
    write_inline(attrs)
  end

  # Tier 2: insert on the primary (GET requests run on the replica, so the role is pinned)
  def write_inline(attrs)
    ActiveRecord::Base.connected_to(role: :writing) { SecurityEvent.write!(attrs) }
  rescue StandardError => e
    # X3 — both down: the event survives as one log line, and engineering hears about it (rate-limited)
    log_lost(attrs, e)
  end

  # S1l / S1m — the reason for a refused bearer token, from OauthBearerAuthenticator's / the controllers' messages.
  # nil for a request with no token at all: that is a client that has not signed in yet, not an attempt (E13).
  # @return [String, nil]
  def bearer_failure_reason(message)
    case message.to_s
    when /missing token/i then nil
    when /deactivated/i then "deactivated"
    when /another organisation|different organisation/i then "entity_mismatch"
    when /add-in tokens|not valid for the mail add-in/i then "wrong_token_type"
    else "invalid"
    end
  end

  # The region this box serves, as stored on every row ("IN", "US")
  def region
    ENV.fetch("CURRENT_SITE", "").strip.upcase.first(5).presence || "IN"
  end

  # One JSON line; never an email, a token or a code
  def log(event, kind:, user_id:, error:)
    Rails.logger.warn("[security_event] #{event} #{{ kind:, user_id:, error: "#{error.class}: #{error.message}".first(300) }.to_json}")
  rescue StandardError
    nil
  end

  # X3 — the event itself goes to the log (no email: the typed email is dropped), plus one exception email per
  # NOTIFY_EVERY so a broken table is noticed without flooding the inbox
  def log_lost(attrs, error)
    line = attrs.slice("kind", "outcome", "door", "user_id", "actor_id", "entity_id", "ip_address", "occurred_at", "uid")
    Rails.logger.warn("[security_event] lost #{line.merge('error' => "#{error.class}: #{error.message}".first(300)).to_json}")
    notify_once(error)
  rescue StandardError
    nil
  end

  def notify_once(error)
    # The cache key exists for NOTIFY_EVERY after the first email
    return unless Rails.cache.write("security_event:lost_notified", true, expires_in: NOTIFY_EVERY, unless_exist: true)
    return unless defined?(ExceptionNotifier)

    ExceptionNotifier.notify_exception(error, data: { message: "security_event write failed; event logged as [security_event] lost" })
  rescue StandardError
    nil
  end
end
