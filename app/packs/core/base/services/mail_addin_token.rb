# frozen_string_literal: true

# Issues the bearer tokens the Outlook task pane and the Gmail add-on authenticate with.
#
# Shared by both add-ins so they cannot drift apart on token lifetime, scope or — most
# importantly — entity pinning. Each token records the entity the user was working in when
# it was issued, so the mail API cannot be used to reach another tenant even if the user
# belongs to several.
#
# Both add-ins are first-party clients whose user has already proven identity through a
# normal Devise session in a top-level browser window, so the token is minted directly
# rather than by running a redirect dance with ourselves. No client secret ever reaches
# either client.
#
# @see OutlookAddinController#oauth_start
# @see GmailAddinController#oauth_start
class MailAddinToken
  APPLICATION_NAME = 'CapHive Mail Add-in'

  # N5 — the exact row create_application makes. Dynamic client registration could also make an
  # app with this name (it is now reserved there, McpClientRegistry), so add-in trust requires the
  # whole server-created shape, not the name alone. Ops still delete any such app the server did
  # not create (docs/security/security_review_2026_10.md "Authentication and session", M2).
  APPLICATION_SHAPE = { name: APPLICATION_NAME, redirect_uri: 'urn:ietf:wg:oauth:2.0:oob', confidential: true }.freeze

  # Matches Doorkeeper's configured access_token_expires_in. When a token expires the
  # add-ins show a Sign in button rather than silently re-authenticating, because both
  # hosts restrict windows opened without a user gesture.
  TTL = 30.days

  # Both add-ins mint their token from a GET (the Office dialog and the Gmail browser tab
  # are plain page loads), and ActiveRecord::Middleware::DatabaseSelector sends GETs to the
  # replica. Writing there raises ActiveRecord::ReadOnlyError, so every write in this class
  # names the writing role explicitly — the same pattern as Doorkeeper's own authorize
  # action (config/initializers/doorkeeper_force_primary.rb).
  #
  # @param user [User]
  # @return [Doorkeeper::AccessToken]
  def self.issue_for(user)
    ActiveRecord::Base.connected_to(role: :writing) do
      Doorkeeper::AccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: 'read',
        expires_in: TTL.to_i,
        use_refresh_token: false,
        entity_id: user.entity_id
      )
    end
  end

  # The token plus the bits of context the add-ins display ("Signed in as …").
  # @param user [User]
  # @return [Hash]
  def self.payload_for(user)
    {
      # L2 — tokens are stored hashed; only the instance just created knows the raw value
      access_token: issue_for(user).plaintext_token,
      expires_at: (Time.current + TTL).iso8601,
      user_name: user.full_name,
      entity_name: user.entity&.name
    }
  end

  # Created on demand so a fresh environment needs no manual OAuth registration step.
  # Confidential, and never used in a redirect flow — hence the placeholder redirect URI.
  #
  # The lookup is split from the create so the common case is a pure read: this is reached
  # from token issuing (a GET, and therefore the replica) and the create must not be
  # attempted unless the row is genuinely missing.
  def self.application
    application_scope.order(:id).first || create_application
  end

  # Whether a presented token was minted for the add-ins rather than for another Doorkeeper
  # client (the MCP server issues tokens against the same server).
  #
  # Matches on the whole set of add-in applications, not one id: oauth_applications has no
  # unique index on `name`, so two simultaneous first-ever sign-ins on a fresh environment
  # can each insert a row. Comparing against every matching id makes such a duplicate
  # harmless instead of invalidating half the tokens in circulation.
  #
  # @param access_token [Doorkeeper::AccessToken]
  # @return [Boolean]
  def self.issued?(access_token)
    application_scope.pluck(:id).include?(access_token.application_id)
  end

  # Read-only, and therefore safe on the replica. N5 — the server-created shape, not just the name.
  def self.application_scope
    Doorkeeper::Application.where(APPLICATION_SHAPE)
  end

  def self.create_application
    ActiveRecord::Base.connected_to(role: :writing) do
      # Found by the whole shape, so a same-named app of another shape is never adopted (N5)
      Doorkeeper::Application.create_with(scopes: 'read').find_or_create_by!(APPLICATION_SHAPE)
    end
  end
end
