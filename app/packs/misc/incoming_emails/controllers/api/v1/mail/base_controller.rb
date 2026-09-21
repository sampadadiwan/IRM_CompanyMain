# frozen_string_literal: true

module Api
  module V1
    module Mail
      # Shared base for the mail add-in API consumed by the Outlook task pane and the
      # Gmail add-on.
      #
      # Inherits ActionController::API rather than ApplicationController, deliberately:
      # ApplicationController pulls in Devise session auth, and neither client can hold a
      # session. Outlook frames the task pane cross-site, where the SameSite=Lax session
      # cookie is never sent — the previous session-based task pane could not have worked
      # in any current browser. Apps Script has no browser context at all.
      #
      # Both clients authenticate with a Doorkeeper bearer token instead.
      # @see docs/modules/mail_addins/mail_addin_review.md
      class BaseController < ActionController::API
        before_action :set_cors_headers
        before_action :authenticate_token!, except: :preflight

        # ActionController::API has none of ApplicationController's rescue_from handlers,
        # so without these an unknown id or a denied record 500s at the client instead of
        # rendering something the add-in can show.
        rescue_from ActiveRecord::RecordNotFound do
          render json: { success: false, errors: ["Record not found."] }, status: :not_found
        end

        rescue_from Pundit::NotAuthorizedError do
          render json: { success: false, errors: ["Access denied."] }, status: :forbidden
        end

        # CORS preflight — the Outlook task pane calls this API from a different origin.
        def preflight
          head :ok
        end

        private

        def set_cors_headers
          response.set_header('Access-Control-Allow-Origin', request.headers['Origin'] || '*')
          response.set_header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
          response.set_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
          response.set_header('Access-Control-Expose-Headers', 'WWW-Authenticate')
        end

        # Resolves the bearer token to a user and entity. Responds 401 with a
        # WWW-Authenticate header so the clients know to run their OAuth flow rather than
        # showing a generic error — the old task pane surfaced expired sessions as
        # "Unexpected token '<'" because it tried to JSON-parse a login redirect.
        # Resolved against the primary deliberately. A token is minted seconds before the
        # add-in's first call, and this API is cookie-less — so DatabaseSelector's
        # session-based "read your own writes" window cannot apply to it, and a GET
        # (/owners) would otherwise validate the new token against a replica that has not
        # replicated it yet, rejecting a user who has just signed in. One row by primary
        # key; the actions' own queries still use whichever role the request selected.
        def authenticate_token!
          ActiveRecord::Base.connected_to(role: :writing) { resolve_token! }
        end

        def resolve_token!
          result = OauthBearerAuthenticator.authenticate(OauthBearerAuthenticator.token_from(request))
          @current_user = result.user
          @current_entity = result.entity

          # This API must only accept tokens minted for the add-ins. Doorkeeper's default
          # scope is `read` and other integrations (the MCP server) issue tokens against
          # the same server, so without this check any such token would be accepted here
          # and could write IncomingEmail rows and upload Documents.
          #
          # MailAddinToken.issued? is a pure read: it must never try to register the client
          # here, because GET requests on this API run against the replica.
          return render_error("This token is not valid for the mail add-in API.", status: :forbidden) unless MailAddinToken.issued?(result.doorkeeper_token)

          # Every query below scopes on current_user.entity_id, so a token minted for a
          # different entity than the user is currently in would read and write the wrong
          # tenant's data. Rather than silently using one or the other, refuse it — the
          # add-in re-authenticates and gets a token for the right entity.
          return if @current_entity.nil? || @current_entity.id == @current_user.entity_id

          render_error("This token was issued for a different organisation. Please sign in again.", status: :forbidden)
        rescue OauthBearerAuthenticator::AuthenticationError => e
          response.set_header('WWW-Authenticate', %(Bearer realm="#{request.base_url}"))
          render json: { error: e.message }, status: :unauthorized
        end

        attr_reader :current_user, :current_entity

        # Pundit needs an explicit user here — ActionController::API has no Devise helper.
        def policy_scope(scope)
          Pundit.policy_scope!(current_user, scope)
        end

        def render_error(message, status: :unprocessable_content)
          render json: { success: false, errors: Array(message) }, status: status
        end
      end
    end
  end
end
