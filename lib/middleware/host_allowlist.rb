# frozen_string_literal: true

# The Host headers this deployment answers to, as one matcher for Rails' HostAuthorization
# (docs/security/security_review_2026_10.md, L5). Off unless ENFORCE_HOST_AUTHORIZATION=1 — see
# config/initializers/security_headers.rb — because a host missed here answers 403 to real users.
#
# Allowed:
#   * BASE_DOMAIN and every subdomain of it (app., dev., each tenant's sub_domain) — per env, from
#     the env's own BASE_DOMAIN (caphive.com, caphive.us, altconnects.com, ...)
#   * every tenant custom domain (entities.domain) and its subdomains, cached for CACHE_TTL so a
#     newly mapped domain starts working within minutes without a deploy
#   * EXTRA_ALLOWED_HOSTS, a comma list for anything else ops route here (exact host names)
# Never checked: the /health_check/* probes (EXCLUDE), which load balancers send by IP.
#
# Rails calls `allowed === host` for objects it does not know, so this class implements #===.
class HostAllowlist
  CACHE_KEY = "host_allowlist/custom_domains"
  CACHE_TTL = 5.minutes

  # HostAuthorization's `exclude:` — requests that skip the check altogether
  EXCLUDE = ->(request) { request.path.start_with?("/health_check") }

  def initialize(env: ENV)
    @env = env
  end

  # L5-2 — true when the Host header (possibly with a port) names this deployment
  def ===(host)
    # Compare host names only: drop the port and any trailing dot, ignore case
    name = host.to_s.downcase.sub(/:\d+\z/, "").chomp(".")
    return false if name.empty?

    # 1. The env's own domain and its subdomains
    return true if within?(name, base_domain)
    # 2. Hosts ops listed explicitly
    return true if extra_hosts.include?(name)

    # 3. A tenant's custom domain (looked up last: it is the only check that may touch the cache/DB)
    custom_domains.any? { |domain| within?(name, domain) }
  end

  private

  # BASE_DOMAIN without a port (development uses "localhost:3001")
  def base_domain
    @env["BASE_DOMAIN"].to_s.downcase.sub(/:\d+\z/, "").presence
  end

  def extra_hosts
    @env["EXTRA_ALLOWED_HOSTS"].to_s.downcase.split(",").map(&:strip).compact_blank
  end

  # The domain itself or any subdomain of it
  def within?(name, domain)
    domain.present? && (name == domain || name.end_with?(".#{domain}"))
  end

  # Distinct custom domains in SQL (a few dozen rows), refreshed every CACHE_TTL
  def custom_domains
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      Entity.where.not(domain: [nil, ""]).unscope(:order).distinct.pluck(:domain).map { |d| d.to_s.downcase.strip }
    end
  end
end
