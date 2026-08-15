# Serves a small, explicitly allowlisted set of user guides to visitors who are NOT signed in.
#
# Why this exists separately from UserGuidesController:
#
# The two-factor screens (mode selection, authenticator enrollment, code entry) all run in the
# pre-sign-in state — Users::TwoFactorController signs the user out and holds only an id in the
# session. Any help link on those pages therefore cannot point at /user_guides/*, because
# UserGuidePolicy requires `user.present?` and the visitor would be bounced to the login page,
# losing the half-finished enrollment. A user who is stuck setting up their authenticator app is
# exactly the user who cannot get past the login page to read about it.
#
# Rather than open the whole guide library, this controller exposes a fixed allowlist. Adding a
# guide here is a deliberate decision that its content is safe for anonymous readers: no tenant
# data, no customer names, nothing that reveals internal structure.
class PublicGuidesController < ApplicationController
  include WithGuideRendering

  layout "public_guide"

  # Nothing here reads tenant data, so all three of the app-wide filters are opted out of:
  # authentication, Pundit's authorize check, and the subdomain -> tenant resolution (which
  # would otherwise bounce the visitor to a tenant microsite mid-enrollment).
  skip_before_action :authenticate_user!
  skip_before_action :set_current_entity
  skip_after_action :verify_authorized

  before_action :force_html_format

  # Guides readable without a login, keyed by the same id used under /user_guides.
  # Both are login-help content reached from the two-factor screens.
  PUBLIC_GUIDE_IDS = %w[
    authenticator_app_setup_user_guide
    two_factor_authentication_user_guide
  ].freeze

  def show
    raw_id = params[:id].to_s.sub(/\.md$/i, "")

    # Allowlist first: an id that is not published stays a 404-equivalent regardless of whether
    # the file exists, so this route can never be walked across the rest of docs/user_guides.
    unless PUBLIC_GUIDE_IDS.include?(raw_id)
      redirect_to new_user_session_path, alert: "Guide not found."
      return
    end

    path = resolve_guide_path(raw_id)
    if path.nil?
      redirect_to new_user_session_path, alert: "Guide not found."
      return
    end

    @guide_id     = raw_id
    @title        = guide_title(raw_id)
    @html_content = render_guide_markdown(path)
  end

  private

  # Guide ids read naturally with no extension; without this a trailing dot in a title-like id
  # would be parsed as a format and blow up template lookup.
  def force_html_format
    request.format = :html
  end
end
