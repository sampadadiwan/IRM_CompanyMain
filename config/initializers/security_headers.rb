# frozen_string_literal: true

# Response headers and Host checking (docs/security/security_review_2026_10.md, L5).
# The report-only CSP itself is configured in content_security_policy.rb.
require_relative "../../lib/middleware/security_headers"
require_relative "../../lib/middleware/host_allowlist"

# Outside Rails' CSP middleware, so on the way out it runs AFTER Rails has written (or skipped)
# the report-only header, and sees whatever CSP a controller set itself (L5-H, L5-3).
Rails.application.config.middleware.insert_before(ActionDispatch::ContentSecurityPolicy::Middleware, SecurityHeaders)

# L5-2 — Host authorization, off by default: ENFORCE_HOST_AUTHORIZATION=1 turns it on per env once
# ops have confirmed every host that legitimately reaches the app (EXTRA_ALLOWED_HOSTS covers the
# odd one out). Unknown hosts then answer 403; health checks are never checked. The session cookie
# keeps domain: :all (session_store.rb) — tenant subdomain redirects depend on it.
if ENV["ENFORCE_HOST_AUTHORIZATION"] == "1"
  Rails.application.config.hosts << HostAllowlist.new
  Rails.application.config.host_authorization = { exclude: HostAllowlist::EXCLUDE }
end
