# frozen_string_literal: true

# The fixed list of security event kinds (OWASP 2026-11 M11, design card ② and ③).
#
# A frozen constant, not configuration: a firm must not be able to mute its own watch, and a kind can't be
# invented at runtime. Each kind names
#   category    — its group, for the screen's filter and cards (sign_in, two_factor, account, access,
#                 support, credential, data)
#   label       — the plain-words name shown on the Security Events screen and in the spreadsheets
#   detail_keys — the only `details` keys that may be stored. Anything else a caller passes is dropped, so a
#                 hook can't leak a token or a code by passing params (E36, X5)
#   alert       — true when the kind can raise an admin alert (SecurityEventAlert decides the rest, D8)
#
# Unknown kinds are a programming error: SecurityEvents.record logs and drops them, never raises (E35).
module SecurityEventCatalogue
  CATEGORIES = {
    "sign_in" => { label: "Sign-in", icon: "ti-login" },
    "two_factor" => { label: "Two-factor", icon: "ti-shield-lock" },
    "account" => { label: "Account", icon: "ti-user-cog" },
    "access" => { label: "Access", icon: "ti-key" },
    "support" => { label: "Support access", icon: "ti-headset" },
    "credential" => { label: "Credentials", icon: "ti-plug" },
    "data" => { label: "Data export", icon: "ti-download" }
  }.freeze

  # The closed list of doors — how the person reached CapHive (design "Door")
  DOORS = {
    "web_password" => "Website",
    "two_factor" => "Website + code",
    "magic_link" => "Sign-in link",
    "password_reset" => "Password reset",
    "mobile" => "Mobile app",
    "api" => "API sign-in",
    "cross_region" => "Region switch",
    "mobile_handoff" => "App to website",
    "mail_addin" => "Mail add-in",
    "oauth" => "Connected app",
    "admin" => "Admin console",
    "system" => "System"
  }.freeze

  KINDS = {
    # ── Sign-in (S1a–S3) ──
    "sign_in.succeeded" => { category: "sign_in", label: "Signed in", detail_keys: %w[origin] },
    "sign_in.failed" => { category: "sign_in", label: "Sign-in failed", detail_keys: %w[reason] },
    # ── Two-factor (T1–T4) ──
    "two_factor.code_failed" => { category: "two_factor", label: "Wrong two-factor code", detail_keys: %w[attempt challenge_ended] },
    "two_factor.enabled" => { category: "two_factor", label: "Two-factor switched on", detail_keys: %w[from to] },
    "two_factor.disabled" => { category: "two_factor", label: "Two-factor switched off", detail_keys: %w[from to] },
    "two_factor.method_set" => { category: "two_factor", label: "Two-factor method set", detail_keys: %w[mode] },
    "two_factor.method_reset" => { category: "two_factor", label: "Two-factor method reset", detail_keys: %w[from] },
    # ── Account (A1–A6) ──
    "password.changed" => { category: "account", label: "Password changed", detail_keys: [] },
    "password.reset_requested" => { category: "account", label: "Password reset requested", detail_keys: [] },
    "phone.changed" => { category: "account", label: "Phone number changed", detail_keys: %w[from to] },
    "account.locked" => { category: "account", label: "Account locked", detail_keys: %w[reason] },
    "account.unlocked" => { category: "account", label: "Account unlocked", detail_keys: [] },
    "account.deactivated" => { category: "account", label: "Account deactivated", detail_keys: [] },
    "account.reactivated" => { category: "account", label: "Account reactivated", detail_keys: [] },
    "firm.deactivated" => { category: "account", label: "Firm deactivated", detail_keys: %w[name] },
    # ── Access (R1–R2) ──
    "role.granted" => { category: "access", label: "Role granted", detail_keys: %w[role resource_type resource_id], alert: true },
    "role.revoked" => { category: "access", label: "Role revoked", detail_keys: %w[role resource_type resource_id], alert: true },
    "support_access.enabled" => { category: "access", label: "Support access switched on", detail_keys: %w[from to scope], alert: true },
    "support_access.disabled" => { category: "access", label: "Support access switched off", detail_keys: %w[from to scope], alert: true },
    # ── Support access (P1–P3) ──
    "support.signed_in_as" => { category: "support", label: "Support signed in as", detail_keys: %w[via], alert: true },
    "support.session_ended" => { category: "support", label: "Support session ended", detail_keys: [] },
    "support.firm_switched" => { category: "support", label: "Support switched into the firm", detail_keys: %w[mapping_id], alert: true },
    "support.switched_back" => { category: "support", label: "Support switched back", detail_keys: %w[mapping_id] },
    # ── Credentials (K1–K3) ──
    "api_token.created" => { category: "credential", label: "API key created", detail_keys: %w[name] },
    "api_token.revoked" => { category: "credential", label: "API key revoked", detail_keys: %w[name] },
    "mobile_device.revoked" => { category: "credential", label: "Phone signed out", detail_keys: %w[name reason] },
    "connected_app.authorised" => { category: "credential", label: "Connected app authorised", detail_keys: %w[app scopes] },
    # ── Data (D1–D4) ──
    "data.exported" => { category: "data", label: "Data exported", detail_keys: %w[what name] }
  }.freeze

  # "What to do" — the per-row popup on the Security Events screen (user requests 2026-11-09: a suggestion per row
  # instead of one general help line, shown in a styled info popup). Each kind has two plain-words parts:
  #   normal — when this event is expected (the popup's green "When this is normal" card)
  #   act    — what to do if it wasn't expected (the amber card); nil means nothing to check (a grey card)
  # A kind whose failed rows need other words has a :failure entry of the same shape.
  SUPPORT_REPORT = "write to support@caphive.com"
  CONFIRM_WITH_PERSON = "Check with the person that it was them. If it wasn't, reset their password and their " \
                        "two-factor method on their user page, and #{SUPPORT_REPORT}.".freeze
  SUPPORT_VISIT = {
    normal: "CapHive support visiting your firm's account, usually because your firm asked for help.",
    act: "If nobody in your firm asked for help, #{SUPPORT_REPORT}."
  }.freeze
  ADVICE = {
    # ── Sign-in ──
    "sign_in.succeeded" => { normal: "Expected whenever the person signs in.",
                             act: "If they didn't sign in at this time, deactivate them on their user page and " \
                                  "#{SUPPORT_REPORT}." },
    "sign_in.failed" => { normal: "One or two failed sign-ins are usually a typo.",
                          act: "Many for one account, or from an IP you don't recognise, may be someone guessing. " \
                               "Ask the person, ask them to change their password, and filter by the IP to see " \
                               "every account it tried." },
    # ── Two-factor ──
    "two_factor.code_failed" => { normal: "One wrong two-factor code is usually a typo.",
                                  act: "Several in a row mean someone may have the password: ask the person to " \
                                       "change it." },
    "two_factor.enabled" => { normal: "Good: the account now asks for a second step at sign-in.", act: nil },
    "two_factor.disabled" => { normal: "Expected only when the person chose to turn two-factor off.",
                               act: CONFIRM_WITH_PERSON },
    "two_factor.method_set" => { normal: "Expected when the person sets up or changes their two-factor method.",
                                 act: CONFIRM_WITH_PERSON },
    "two_factor.method_reset" => { normal: "Expected when the person lost their phone and asked an admin or " \
                                           "CapHive support to reset their method.",
                                   act: CONFIRM_WITH_PERSON },
    # ── Account ──
    "password.changed" => { normal: "Expected when the person changes or resets their password.",
                            act: CONFIRM_WITH_PERSON },
    "password.reset_requested" => { normal: "Expected when the person forgot their password.",
                                    act: "Many requests they didn't make mean someone is trying their account: " \
                                         "#{SUPPORT_REPORT}." },
    "phone.changed" => { normal: "Expected when the person changed their number. Two-factor codes now go to the " \
                                 "new number.",
                         act: CONFIRM_WITH_PERSON },
    "account.locked" => { normal: "The account locks after 6 wrong passwords in a row.",
                          act: "If the person didn't try to sign in, someone else may have: ask them to reset " \
                               "their password." },
    "account.unlocked" => { normal: "The person can sign in again.", act: nil },
    "account.deactivated" => { normal: "Expected when someone leaves or no longer needs access.",
                               act: "If it wasn't intended, reactivate the person on their user page." },
    "account.reactivated" => { normal: "Expected when someone needs access again.",
                               act: "If they shouldn't have access, deactivate them on their user page." },
    "firm.deactivated" => { normal: "Expected only when the firm stops using CapHive.",
                            act: "If it wasn't intended, #{SUPPORT_REPORT}." },
    # ── Access ──
    "role.granted" => { normal: "Expected when someone in your firm gives this access.",
                        act: "If nobody meant to, remove the role on the person's user page and " \
                             "#{SUPPORT_REPORT}." },
    "role.revoked" => { normal: "Expected when someone in your firm removes this access.",
                        act: "If nobody meant to, give the role back on the person's user page." },
    "support_access.enabled" => { normal: "Expected when your firm asks CapHive support for help with this " \
                                          "person's account.",
                                  act: "If nobody asked, switch support access off on the person's user page." },
    "support_access.disabled" => { normal: "CapHive support can no longer sign in as this person. Switch it back " \
                                           "on if you still need their help.",
                                   act: nil },
    # ── Support ──
    "support.signed_in_as" => SUPPORT_VISIT,
    "support.session_ended" => SUPPORT_VISIT,
    "support.firm_switched" => SUPPORT_VISIT,
    "support.switched_back" => SUPPORT_VISIT,
    # ── Credentials and data ──
    "api_token.created" => { normal: "Expected when the person sets up a script or an integration.",
                             act: "If they don't need it, revoke the key on their API tokens page." },
    "api_token.revoked" => { normal: "The key no longer works.", act: nil },
    "mobile_device.revoked" => { normal: "The phone is signed out of the CapHive app.", act: nil },
    "connected_app.authorised" => { normal: "Expected when the person connects an app, such as an AI assistant.",
                                    act: "If they didn't mean to, ask them to sign out of it and " \
                                         "#{SUPPORT_REPORT}." },
    "data.exported" => { normal: "Expected when the person downloads reports or data.",
                         act: "If they weren't expected to download this, ask them why and #{SUPPORT_REPORT}." }
  }.freeze
  # For a kind with no wording of its own
  DEFAULT_ADVICE = { normal: "Expected when someone in your firm did this.",
                     act: "If it wasn't expected, #{SUPPORT_REPORT}." }.freeze

  # A stored detail value is short text: a name, a reason, a role — never a document
  MAX_DETAIL_LENGTH = 200

  module_function

  # @param kind [String]
  # @return [Hash] the kind's entry
  # @raise [KeyError] for a kind that is not in the catalogue (E35)
  def fetch(kind)
    KINDS.fetch(kind.to_s)
  end

  def kinds
    KINDS.keys
  end

  def label(kind)
    KINDS.dig(kind.to_s, :label) || kind.to_s
  end

  # The "What to do" popup's two parts for a row: the kind's :failure wording on a failed row when it has one, else
  # the kind's own, else the default
  # @param kind [String]
  # @param failure [Boolean] the row's outcome
  # @return [Hash{Symbol=>String,nil}] normal:, act: (nil act = nothing to check)
  def advice(kind, failure: false)
    # The kind's wording (none for an unknown kind)
    entry = ADVICE[kind.to_s]
    return DEFAULT_ADVICE if entry.nil?

    # A failed row uses its own wording only where the kind has one
    (failure && entry[:failure]) || entry.slice(:normal, :act)
  end

  def category_label(category)
    CATEGORIES.dig(category.to_s, :label) || category.to_s
  end

  def door_label(door)
    DOORS[door.to_s] || door.to_s.humanize
  end

  # E36 — keeps only the kind's allowlisted keys, each value cut to short text. Booleans and integers stay
  # as they are (attempt numbers, challenge_ended), everything else becomes a string.
  # @return [Hash{String=>Object}]
  def slice_details(kind, details)
    # The allowlist for this kind; a kind with none stores nothing
    allowed = fetch(kind)[:detail_keys]
    (details || {}).to_h.stringify_keys.slice(*allowed).each_with_object({}) do |(key, value), out|
      # Skip empty values, so a row never carries "role": ""
      next if value.nil? || value == ""

      out[key] = case value
                 when true, false, Integer then value
                 else value.to_s.truncate(MAX_DETAIL_LENGTH)
                 end
    end
  end
end
