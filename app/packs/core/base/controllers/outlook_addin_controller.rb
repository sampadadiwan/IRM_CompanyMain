# Serves the Outlook task pane and issues the bearer token it authenticates with.
#
# Auth model, and why it is shaped this way:
#
# The task pane is an iframe hosted by outlook.office.com — a cross-site context where our
# SameSite=Lax session cookie is never sent. The previous version of this controller ran
# `authenticate_user!` on the task pane and so could not have worked in any current
# browser: every user would have been bounced to a sign-in page rendered inside a 320px
# pane, where the login POST would have failed for the same reason.
#
# The window Office opens via displayDialogAsync is a *top-level* window, so cookies do
# flow there. Sign-in happens there, against the normal Devise session. Because the add-in
# is a first-party client and the user's identity is already proven by that session, the
# dialog mints a Doorkeeper access token directly rather than running a redirect dance
# with itself. The token is handed back to the pane over Office's dialog messaging
# channel, and the pane uses it as a bearer token against /api/v1/mail/*.
#
# No client secret and no session cookie ever reaches the pane's JavaScript.
#
# @see docs/technical/mail_addin_review.md
class OutlookAddinController < ApplicationController
  # Origins Office frames the task pane from. Outlook on the web hosts the pane at
  # outlook.office.com (or the -sdf ring for Targeted Release, or outlook.live.com for
  # consumer accounts); Outlook desktop and new Outlook use an embedded WebView2 which
  # loads the pane from these same hosts.
  OFFICE_FRAME_ANCESTORS = %w[
    https://outlook.office.com
    https://outlook.office365.com
    https://outlook-sdf.office.com
    https://outlook-sdf.office365.com
    https://outlook.live.com
    https://*.outlook.com
    https://*.office.com
    https://*.office365.com
    https://*.microsoft.com
  ].freeze

  # The task pane shell is deliberately unauthenticated — it renders, then acquires a
  # token for itself. Everything that touches data goes through the token-authenticated API.
  skip_before_action :authenticate_user!, only: [:taskpane]
  skip_after_action :verify_authorized, only: %i[taskpane oauth_start investors]

  after_action :allow_office_framing, only: [:taskpane]

  helper_method :simulator_enabled?

  layout 'outlook_addin'

  def taskpane
    skip_authorization
  end

  # Opened in the Office dialog (a top-level window). authenticate_user! applies, so Devise
  # prompts here if there is no session — which is the one place a login form actually works.
  def oauth_start
    skip_authorization

    @token_payload = MailAddinToken.payload_for(current_user)

    respond_to do |format|
      format.html { render :oauth_start, layout: false }
      # JSON is for the development simulator, which has no Office dialog channel to
      # receive the token over. Same-origin and session-authenticated exactly like the
      # HTML branch; restricted to non-production so the token cannot be lifted by a
      # session-riding request against a deployed host.
      format.json do
        return head :not_found unless simulator_enabled?

        render json: @token_payload
      end
    end
  end

  # Legacy endpoint for the pre-rewrite task pane: returns every investor in the entity
  # with no search or limit. Superseded by GET /api/v1/mail/owners, which is scoped,
  # searchable and capped.
  # @deprecated
  def investors
    skip_authorization
    @investors = policy_scope(Investor).order(:investor_name)
    render json: @investors.map { |i| { id: i.id, investor_name: i.investor_name } }
  end

  private

  # Rails defaults to X-Frame-Options: SAMEORIGIN, which renders the task pane as a blank
  # frame everywhere it actually runs — the host page is outlook.office.com, never our own
  # origin. X-Frame-Options has no working allowlist form (ALLOW-FROM was never implemented
  # by Chrome and is removed from Firefox), so it is dropped in favour of a CSP
  # frame-ancestors allowlist, which is the directive that supersedes it.
  #
  # Note this is deliberately an allowlist and not a blanket removal: without
  # frame-ancestors any site could frame the pane.
  def allow_office_framing
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] =
      "frame-ancestors 'self' #{OFFICE_FRAME_ANCESTORS.join(' ')}"
  end

  # The browser simulator lets the pane run in a plain tab with no Outlook host, and its
  # JSON branch of oauth_start hands a bearer token to any request carrying a session
  # cookie. That is fine on a developer's machine and is a token-leak vector on any
  # reachable host, so staging must opt in explicitly rather than inherit it from
  # "not production".
  def simulator_enabled?
    Rails.env.local? || ENV['MAIL_ADDIN_SIMULATOR'] == 'true'
  end
end
