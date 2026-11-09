# Brokers sign-in for the Gmail add-on.
#
# The add-on cannot show a CapHive login form itself: Gmail add-ons render Google's
# CardService widgets, which have no password input type, and the previous build collected
# the user's CapHive password in a plaintext TextInput. That exposed the password on
# screen, bypassed SSO and MFA entirely, and is a standard Marketplace rejection.
#
# Instead the add-on opens this endpoint in a normal browser tab, where the Devise session
# — and therefore any SSO or MFA the tenant uses — works as it does everywhere else. A
# bearer token is minted for the authenticated user and handed back to Apps Script through
# Google's usercallback mechanism, using the state token the add-on generated.
#
# SECURITY (H12, docs/security/security_review_2026_10.md "H12 — Gmail add-in sign-in"):
# the token used to be minted on the GET, for any https://script.google.com URL whose path
# merely contained "/usercallback". Anyone could publish their own Apps Script project, so a
# single link clicked by a signed-in user handed that user's 30-day token to the attacker's
# script. Now:
#   1. the callback must be exactly /macros/d/<script id>/usercallback?state=<non-blank>, and
#      the script id must be one of THIS environment's published add-on projects
#      (credentials gmail_addin.script_ids — IN and US are separate lists);
#   2. the GET only renders a confirm page; the token is minted by its CSRF-protected POST,
#      so a link alone can no longer complete the sign-in;
#   3. McpController refuses mail add-in tokens, so even a leaked one cannot read over /mcp.
#
# @see docs/modules/mail_addins/mail_addin_review.md
class GmailAddinController < ApplicationController
  # Apps Script hands control back through this host only. Validated strictly, because the
  # redirect carries an access token in its query string — accepting an arbitrary
  # redirect_uri here would be an open redirect that leaks credentials.
  ALLOWED_CALLBACK_HOST = 'script.google.com'.freeze

  # The only callback shape the add-on ever sends (addons/gmail/Code.gs getCallbackUrl): the
  # script id is captured so it can be checked against the allowlist. Anchored at both ends,
  # so "/macros/d/<id>/usercallback/extra" or "/x/macros/d/<id>/usercallback" do not pass.
  CALLBACK_PATH = %r{\A/macros/d/(?<script_id>[A-Za-z0-9_-]+)/usercallback\z}

  # Local development only: comma-separated ids of a developer's own test deployment, so a
  # sideloaded add-on can sign in without editing credentials. Never read in a deployed env.
  DEV_SCRIPT_IDS_ENV = 'GMAIL_ADDIN_DEV_SCRIPT_IDS'.freeze

  skip_after_action :verify_authorized, only: %i[oauth_start oauth_confirm]

  # The script ids of this environment's published add-on projects.
  #
  # Read from per-environment credentials (gmail_addin.script_ids) so the IN and US servers
  # each list only their own project — a token minted here is meaningless at the other region
  # anyway, and sharing the list would let one region's add-on sign in at the other.
  # Accepts an array or a comma-separated string, so either credentials style works.
  #
  # @return [Array<String>]
  def self.allowed_script_ids
    # The environment's own published projects
    ids = Array(Rails.application.credentials.dig(:gmail_addin, :script_ids))
    # A developer's sideloaded test deployment, on a developer machine only
    ids += [ENV.fetch(DEV_SCRIPT_IDS_ENV, nil)] if Rails.env.development?
    # Split comma lists, trim, and drop blanks so a stray "," cannot allow an empty id
    ids.flat_map { |value| value.to_s.split(',') }.map(&:strip).compact_blank
  end

  # GET — opened in a browser tab by the add-on's sign-in link. authenticate_user! applies,
  # so Devise prompts normally when there is no session.
  #
  # Mints nothing: a GET is what a link (or an <img>, or a prefetch) triggers without the
  # user deciding anything, so it only shows who is about to be connected and asks.
  def oauth_start
    skip_authorization

    # H12-1, H12-2 — an unlisted script id or an altered callback is refused outright
    @callback = parsed_callback_uri
    return render_invalid_callback if @callback.nil?

    # H12-3 — a valid callback still only gets the confirm page; no token exists yet
    render :oauth_start, layout: 'devise'
  end

  # POST — the confirm page's button. Rails' CSRF check applies, so only a form rendered by
  # this server in the user's own session can reach here.
  def oauth_confirm
    skip_authorization

    # Re-validated on the POST: the hidden field is user-controlled, so the confirm page
    # having shown a valid URI says nothing about what was submitted
    callback = parsed_callback_uri
    return render_invalid_callback if callback.nil?

    # H12-H — the user confirmed: mint the token and hand it to the add-on's callback
    payload = MailAddinToken.payload_for(current_user)
    # M11 S1k — the add-on now holds a token for this user
    SecurityEvents.record("sign_in.succeeded", user: current_user, door: "mail_addin")
    callback.query = [callback.query, {
      token: payload[:access_token],
      expires_at: payload[:expires_at],
      user_name: payload[:user_name]
    }.to_query].join('&')

    # allow_other_host is required and safe here: the destination has been verified to be
    # one of this environment's own Apps Script projects.
    redirect_to callback.to_s, allow_other_host: true
  end

  private

  # Same answer for every refusal, so the response does not explain which check failed
  def render_invalid_callback
    render plain: 'Invalid sign-in callback address.', status: :bad_request
  end

  # @return [URI::HTTPS, nil] the callback URI when it is one of this environment's add-on
  #   projects' usercallback, carrying a state token and nothing else
  def parsed_callback_uri
    raw = params[:redirect_uri].to_s
    return nil if raw.blank?

    uri = URI.parse(raw)
    # Scheme, exact host (not suffix: "script.google.com.evil.test" must not pass), default
    # port, and no userinfo or fragment smuggled around the host
    return nil unless uri.is_a?(URI::HTTPS) && uri.host == ALLOWED_CALLBACK_HOST
    return nil unless uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?

    # H12-2 — the exact add-on path, no prefix or suffix
    match = CALLBACK_PATH.match(uri.path)
    return refuse_callback('path') if match.nil?

    # H12-1 — the script id must be this environment's own project
    return refuse_callback("script id #{match[:script_id]}") unless self.class.allowed_script_ids.include?(match[:script_id])

    # The add-on sends exactly one query key, a non-blank state token; anything else (a
    # second key, a repeated state, no state) is not something the add-on produced
    query = URI.decode_www_form(uri.query.to_s)
    return refuse_callback('query') unless query.size == 1 && query.first.first == 'state' && query.first.last.present?

    uri
  rescue URI::InvalidURIError, ArgumentError
    # Unparseable URI, or a malformed query string
    nil
  end

  # Logs why a callback was refused (ops need this while adding a new project's id), and
  # returns nil so callers can `return refuse_callback(...)`. Never logs the state token.
  def refuse_callback(reason)
    Rails.logger.warn("[GmailAddin] refused sign-in callback (#{reason}) for user_id=#{current_user&.id}")
    nil
  end
end
