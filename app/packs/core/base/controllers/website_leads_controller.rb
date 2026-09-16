# Demo requests from the public website.
#
# Two audiences in one controller, with sharply different access:
#
#   create / options   PUBLIC. Unauthenticated, CSRF-exempt, cross-origin. The
#                      only write endpoint of its kind in this app.
#   index / show       CapHive staff only, via WebsiteLeadPolicy.
#
# The filter skips below are scoped with `only: %i[create options]` for exactly
# that reason. A blanket skip would silently open the admin screens to the
# internet, which is the one mistake this file must not make.
#
# See docs/modules/website/website_lead_capture.md.
class WebsiteLeadsController < ApplicationController
  # Nothing on the public path reads or writes tenant data, so the three app-wide
  # filters from WithAuthentication are opted out of for those actions only:
  # authentication, Pundit's authorize check, and subdomain -> tenant resolution
  # (which would otherwise try to resolve a tenant from app.caphive.com).
  skip_before_action :authenticate_user!, only: %i[create options]
  skip_before_action :set_current_entity, only: %i[create options]
  skip_after_action  :verify_authorized,  only: %i[create options]

  # Required for a cross-origin POST that carries no session. Safe here ONLY
  # because these actions are unauthenticated and write solely to their own
  # table — there is no user context an attacker could forge into. Do not copy
  # this onto anything that reads tenant data.
  skip_before_action :verify_authenticity_token, only: %i[create options]

  before_action :set_cors_headers, only: %i[create options]

  # verify_authorized is declared `except: %i[index search bulk_actions]`, so the
  # index would otherwise pass the check without ever consulting a policy.
  after_action :verify_authorized, only: :index

  # ---- public ----

  # Preflight. Not actually triggered by today's client — a multipart POST
  # carrying only Accept and Content-Type is a CORS-simple request — but present
  # so that adding any custom header to the form later does not break submission
  # with a failure nobody can reproduce from the server logs.
  def options
    head :no_content
  end

  def create
    result = WebsiteLeadCreate.call(
      params: lead_params,
      # Server-side provenance. Taken from the request, never from the payload:
      # a client that can set its own IP or timestamp can poison every abuse
      # control and every channel report built on this table.
      request_ip: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referer
    )

    if result.success?
      # A discarded bot gets the same 200 as a real lead. Telling it which check
      # it tripped is telling it what to change.
      render json: { status: "ok" }, status: :ok
    else
      render json: { status: "error", errors: result[:errors] || {} }, status: :unprocessable_entity
    end
  end

  # ---- staff ----

  def index
    authorize WebsiteLead
    skip_policy_scope

    @pagy, @website_leads = pagy(WebsiteLead.recent_first)
    @bread_crumbs = { t("top_menus.website_leads") => nil }
  end

  def show
    @website_lead = WebsiteLead.find(params[:id])
    authorize @website_lead

    @bread_crumbs = { t("top_menus.website_leads") => website_leads_path, @website_lead.name => nil }
  end

  private

  # Permitted explicitly rather than permit!: this is anonymous input, and an
  # unfiltered hash reaching the model is how mass-assignment bugs happen. The
  # underscore-prefixed keys are control fields the operation consumes and drops
  # (_hp honeypot, _ts render stamp) or stores as provenance (_source_page).
  def lead_params
    params.permit(
      :name, :email, :firm, :role, :message,
      :_hp, :_ts, :_source_page, :_subject,
      *WebsiteLead::UTM_FIELDS
    )
  end

  # The website hosts are already declared once, for lib/middleware/website.rb.
  # Reuse them rather than hardcoding caphive.com: staging is altconnects.com and
  # would otherwise be the one environment where this is first tested and fails.
  #
  # Ports are stripped for the same reason the middleware strips them
  # (lib/middleware/website.rb#website_hosts): a dev value like
  # caphive.localhost:3001 must compare equal to the bare host.
  def allowed_website_hosts
    ENV["WEBSITE_HOSTS"].to_s.split(",")
                        .map { |host| host.strip.downcase.sub(/:\d+\z/, "") }
                        .reject(&:empty?)
  end

  # Matches on the origin's HOST, not on the whole origin string.
  #
  # An exact string match would have to enumerate ports, and the port is exactly
  # what differs between environments: production is https://caphive.com with no
  # port, dev is http://caphive.localhost:3001. Enumerating them is how this ends
  # up working in production and failing the first time anyone tests it locally.
  #
  # The scheme is still constrained to http/https, so a file:// or chrome-
  # extension:// origin never matches, and the host must appear in WEBSITE_HOSTS
  # — which an attacker cannot influence.
  def allowed_origin?(origin)
    return false if origin.blank?

    uri = URI.parse(origin)
    %w[http https].include?(uri.scheme) && allowed_website_hosts.include?(uri.host.to_s.downcase)
  rescue URI::InvalidURIError
    # A malformed Origin header is not an allowed one. Never raise: this runs on
    # anonymous input and a 500 here would be a trivially triggerable outage.
    false
  end

  # Echo the caller's own origin back, never a wildcard, and never
  # Access-Control-Allow-Credentials — the client sends no cookies and must not
  # start: this endpoint has no session to authenticate against.
  #
  # An unrecognised origin gets NO CORS header at all, which is what makes the
  # browser refuse to hand the response to the calling script.
  def set_cors_headers
    origin = request.headers["Origin"]
    # Vary is set regardless of the match, so an intermediary cache can never
    # serve one origin's response (with its header) to a different origin.
    response.set_header("Vary", [response.get_header("Vary"), "Origin"].compact.join(", "))
    return unless allowed_origin?(origin)

    response.set_header("Access-Control-Allow-Origin", origin)
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Accept, Content-Type")
    response.set_header("Access-Control-Max-Age", "86400")
  end
end
