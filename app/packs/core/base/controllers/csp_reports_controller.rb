# frozen_string_literal: true

# Receives the browser's Content-Security-Policy violation reports (the report-only policy in
# config/initializers/content_security_policy.rb; docs/security/security_review_2026_10.md, L5).
#
# Browsers send these without cookies or a CSRF token, so this is an unauthenticated API endpoint
# (ActionController::API: no session, no CSRF), throttled per IP in rack_attack.rb. It only logs:
# one compact line per violation, query strings stripped from every URL so a token in a page's URL
# never reaches the log. Always 204 — a browser does nothing with the answer.
class CspReportsController < ActionController::API
  # A report is a few hundred bytes; anything far bigger is not a browser report
  MAX_BODY_BYTES = 16.kilobytes

  # POST /csp_reports
  def create
    # L5-1 — read the raw body (application/csp-report and application/reports+json have no
    # Rails parser), capped so a large post cannot make us parse or log much
    raw = request.body.read(MAX_BODY_BYTES + 1).to_s
    violations(raw).each { |violation| log(violation) } if raw.bytesize <= MAX_BODY_BYTES

    head :no_content
  end

  private

  # The violation hashes in either report format, or [] when the body is not JSON
  def violations(raw)
    data = JSON.parse(raw)
    # report-uri format: {"csp-report": {...}}
    return [data["csp-report"]] if data.is_a?(Hash) && data["csp-report"].is_a?(Hash)
    # Reporting API format: [{"type": "csp-violation", "body": {...}}, ...]
    return data.filter_map { |entry| entry["body"] if entry.is_a?(Hash) && entry["body"].is_a?(Hash) } if data.is_a?(Array)

    []
  rescue JSON::ParserError
    []
  end

  # One log line per violation, in both formats' key spellings
  def log(violation)
    page = without_query(violation["document-uri"] || violation["documentURL"])
    directive = violation["violated-directive"] || violation["effectiveDirective"] || violation["effective-directive"]
    blocked = without_query(violation["blocked-uri"] || violation["blockedURL"])
    Rails.logger.warn("[csp_report] directive=#{directive.to_s.first(100)} blocked=#{blocked} page=#{page}")
  end

  # Drops the query and fragment from a URL, and caps its length
  def without_query(url)
    url.to_s.split(/[?#]/, 2).first.to_s.first(300)
  end
end
