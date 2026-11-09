# H4 (OWASP review 2026-11) — the host headless Chrome loads a PDF page's assets from.
#
# FerrumPdf::Controller#render_pdf passes `request.base_url` to the renderer, which rewrites every relative
# src="/…" in the page to that host. request.base_url honours X-Forwarded-Host, which nginx passes through
# unchanged, so a signed-in user who asked for their own commitment PDF with
#   X-Forwarded-Host: evil.example
# made Chrome on the app server load and run evil.example's JavaScript. That script could read internal
# addresses (Elasticsearch on the data box, the AWS metadata service) and the result came back inside the PDF.
#
# This keeps the request's host when it is one of ours, so every real case renders exactly as before:
#   - the configured HOST (app.caphive.com)
#   - BASE_DOMAIN or any subdomain of it (a firm's microsite, tenant1.caphive.com)
#   - a firm's own mapped domain (Entity#domain, as WithAuthentication#set_current_entity resolves it)
#   - any host in development and test (Cucumber runs on a random local port)
# Anything else renders against the configured HOST instead.
module WithTrustedPdfHost
  extend ActiveSupport::Concern

  private

  # Same signature and body as FerrumPdf::Controller#render_pdf (ferrum_pdf 0.3.0), with the host checked.
  # Included into ApplicationController, so it is found before the gem's module on ActionController::Base.
  # Private: a public method on ApplicationController would count as an action of every controller (the gem's
  # copy is exempt only because it lives on ActionController::Base). Callers use it implicitly inside actions.
  def render_pdf(pdf_options: {}, **rendering)
    content = render_to_string(**rendering.with_defaults(formats: [:html]))

    FerrumPdf.render_pdf(
      html: content,
      host: "#{request.protocol}#{trusted_pdf_host}/",
      protocol: request.protocol,
      pdf_options: pdf_options
    )
  end

  # @return [String] host[:port] for asset URLs: the request's when trusted, else the configured HOST
  def trusted_pdf_host
    return request.host_with_port if Rails.env.local? || pdf_host_trusted?(request.host)

    Rails.logger.warn("[pdf] untrusted host #{request.host.to_s.truncate(100).inspect}; rendering against HOST")
    ENV.fetch("HOST", nil).presence || request.host_with_port
  end

  # @param host [String] the request's host, without port
  def pdf_host_trusted?(host)
    host = host.to_s.downcase
    # ENV values may carry a port ("localhost:3001"); compare host names only
    configured = ENV.fetch("HOST", nil).to_s.split(":").first.to_s.downcase
    base = ENV.fetch("BASE_DOMAIN", nil).to_s.split(":").first.to_s.downcase

    # Our main host, our base domain, or one of its subdomains
    return true if host.present? && host == configured
    return true if base.present? && (host == base || host.end_with?(".#{base}"))

    # A firm's own mapped domain (index_entities_on_domain), the same lookup set_current_entity makes
    Entity.exists?(domain: request.domain)
  end
end
