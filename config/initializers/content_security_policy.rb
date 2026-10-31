# frozen_string_literal: true

# Content Security Policy, phase 1 (docs/security/security_review_2026_10.md, L5).
#
# Two headers go out on every response:
#
#   1. Content-Security-Policy-Report-Only — the full policy below, built by Rails. It blocks
#      nothing; browsers POST what it WOULD have blocked to /csp_reports (CspReportsController),
#      so the inline scripts and handlers in ~40 views and any CDN missing from the allowlist
#      show up before the policy is ever enforced (L5-H, L5-1).
#   2. Content-Security-Policy — only object-src 'none'; base-uri 'self'; frame-ancestors 'self',
#      enforced now. Added by SecurityHeaders (lib/middleware/security_headers.rb, wired up in
#      config/initializers/security_headers.rb), because Rails builds only one CSP header per
#      response. form-action is deliberately not enforced: the OAuth consent screen redirects
#      off-site. frame-ancestors 'self' matches the X-Frame-Options: SAMEORIGIN Rails already
#      sends; the Outlook task pane keeps its own frame-ancestors allowlist (L5-3).
#
# Allowlist: the importmap CDN (jsDelivr), the script/style/font CDNs the layouts and views load,
# Office JS (appsforoffice.microsoft.com), Mapbox, and GTM / Facebook on the website layouts.
Rails.application.configure do
  # Hosts scripts are loaded from (a report names anything else)
  script_hosts = %w[
    https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://cdn.datatables.net https://unpkg.com
    https://code.jquery.com https://cdn.sheetjs.com https://releases.transloadit.com https://vjs.zencdn.net
    https://appsforoffice.microsoft.com https://api.mapbox.com https://cdn.tailwindcss.com
    https://www.googletagmanager.com https://www.googleadservices.com https://connect.facebook.net
  ]
  # Hosts stylesheets are loaded from
  style_hosts = %w[
    https://fonts.googleapis.com https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://cdn.datatables.net
    https://unpkg.com https://releases.transloadit.com https://vjs.zencdn.net https://api.mapbox.com
  ]

  config.content_security_policy do |policy|
    policy.default_src :self
    # Scripts: own origin, the CDNs above, plus the per-request nonce (added by Rails below)
    policy.script_src :self, *script_hosts
    # Styles: inline style attributes are everywhere in the views, so 'unsafe-inline' stays
    policy.style_src :self, :unsafe_inline, *style_hosts
    policy.font_src :self, :data, "https://fonts.gstatic.com", "https://cdn.jsdelivr.net", "https://cdnjs.cloudflare.com"
    # Uploaded documents, avatars and charts come from S3 and many third-party hosts
    policy.img_src :self, :data, :blob, :https
    # Fetch/XHR to our own API and S3 uploads, plus ActionCable's websocket
    policy.connect_src :self, :https, :wss
    # E-sign and help iframes, document previews (officeapps), guide videos
    policy.frame_src :self, :https
    policy.media_src :self, :blob, :https
    policy.worker_src :self, :blob
    # The three directives SecurityHeaders also enforces, so reports and enforcement agree
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :self
    # Where browsers send violation reports (CspReportsController, throttled in rack_attack.rb)
    policy.report_uri "/csp_reports"
  end

  # A fresh random nonce per request (not the session id, which a first request may not have).
  # javascript_importmap_tags and csp_meta_tag pick it up automatically.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  # Nonce scripts only: styles keep 'unsafe-inline', which a style nonce would switch off
  config.content_security_policy_nonce_directives = %w[script-src]

  # Phase 1: report, never block. Enforcement of the full policy is a later, separate change.
  config.content_security_policy_report_only = true
end
