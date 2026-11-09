# Who MUST use two-factor authentication, and from when (OWASP 2026-11 finding M8).
#
# Two inputs, both outside the database on purpose:
#   * REQUIRED_2FA_ROLES — the one place the rule's roles are named. CapHive staff only
#     (support, super) by user decision 2026-11-09; adding company admins later is one line.
#   * ENV["REQUIRED_2FA_ENFORCE_FROM"] — an ISO date, set separately on each region's box
#     (the same date in IN and US). Unset = the rule is off, which is also the rollback.
#
# The date gives each region a STAGE, worked out at every request from the app time zone
# (New Delhi), so enforcement starts at 00:00 IST on the date:
#
#   env value           stage before the date   stage on / after the date
#   unset / blank       :off                    :off
#   2026-12-01          :notice                 :enforced
#   2026-13-01 (typo)   :enforced (+ error log) :enforced            — fail closed (design D4)
#
# Nothing here is stored per user. TwoFactorAuthenticatable#two_factor_required? combines the
# stage with the user's cached roles, and every sign-in door asks #two_factor_applies?.
#
# openspec/changes/require-2fa-privileged-roles — design card ①, decisions D1 and D4.
module RequiredTwoFactor
  # The roles that must use two-factor once the region's date is reached. Order matters only
  # for #role_label: a support user switched into a client also holds company_admin, and a
  # user holding both support and super reads "Support" (E12).
  REQUIRED_2FA_ROLES = %i[support super].freeze

  # The env var ops sets on each region's box (lld.md "Configuration and Rollout").
  ENV_KEY = "REQUIRED_2FA_ENFORCE_FROM".freeze

  class << self
    # The parsed enforcement date, memoised for the life of the process (a change needs a
    # restart, like every other env switch).
    #
    # @return [Date] the date enforcement starts
    # @return [nil] no date configured — the rule is off
    # @return [Symbol] :invalid when the value does not parse (logged once; treated as enforced)
    def enforce_from
      # defined? rather than ||=, so a memoised nil ("off") is not re-read on every request
      return @enforce_from if defined?(@enforce_from)

      @enforce_from = parse_env(ENV.fetch(ENV_KEY, nil))
    end

    # The region's stage on `today`.
    #
    # @param today [Date] defaults to the app time zone's today (00:00 IST boundary, E1/E2)
    # @return [Symbol] :off, :notice or :enforced
    def stage(today = Time.zone.today)
      date = enforce_from
      # E3 — no date configured: today's behaviour everywhere
      return :off if date.nil?
      # E4 — an unparseable date fails closed: "enforced" only means "set up at next sign-in"
      return :enforced if date == :invalid

      # E1 / E2 — enforced from the first minute of the date, notice until then
      today >= date ? :enforced : :notice
    end

    # @return [Boolean] true once the region's date has been reached (or the date is unreadable)
    def enforced?
      stage == :enforced
    end

    # The label shown on the set-up screen and the banner: the first required role the user
    # holds, in REQUIRED_2FA_ROLES order ("Support" before "Super").
    #
    # @param user [User]
    # @return [String, nil] nil when the user holds no required role
    def role_label(user)
      role = REQUIRED_2FA_ROLES.find { |r| user.has_cached_role?(r) }
      role&.to_s&.titleize
    end

    # Forgets the memoised date so the next call re-reads the env. Used by the Cucumber env step
    # (and its After hook) — production reads the env once per process.
    def reset!
      remove_instance_variable(:@enforce_from) if defined?(@enforce_from)
      @invalid_logged = false
    end

    private

    # @param value [String, nil] the raw env value
    # @return [Date, nil, Symbol] see #enforce_from
    def parse_env(value)
      # Unset or blank: the rule is off
      return nil if value.to_s.strip.empty?

      Date.iso8601(value.to_s.strip)
    rescue Date::Error
      # D4 — a typo must not silently switch the control off; say so once per process
      unless @invalid_logged
        Rails.logger.error("[two_factor] #{ENV_KEY} unparseable — enforcing (value=#{value.to_s.strip.inspect})")
        @invalid_logged = true
      end
      :invalid
    end
  end
end
