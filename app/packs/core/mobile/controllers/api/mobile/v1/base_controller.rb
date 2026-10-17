# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # Base for the LP mobile app's API (openspec/changes/lp-mobile-app, design card ④).
      #
      # ActionController::API, not ApplicationController: the phone holds no session cookie, and
      # ApplicationController's Devise session auth would accept ANY devise-api token through
      # WithAuthentication#authenticate_user! — including one minted by devise-api's own
      # /users/tokens/sign_in, which never asks for a two-factor code. Here a token is accepted
      # only when it is the current token of a live MobileDevice (X7), and every read goes
      # through the existing Pundit policies, so the app can never see more than the website.
      class BaseController < ActionController::API
        include Pundit::Authorization
        include WithLocale

        # The oldest app build the server still talks to (X9). Per-region credential.
        DEFAULT_MIN_APP_VERSION = "1.0.0"
        PER_PAGE = 25

        before_action :require_app_version!
        before_action :authenticate_mobile_device!
        after_action :verify_authorized, unless: :skip_authorization_check?

        # Out-of-scope records are "not found", never "forbidden", so the API does not confirm
        # that a record exists (X8, X17, X18)
        rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError do
          render_error("not_found", status: :not_found)
        end
        rescue_from ActionController::ParameterMissing do
          render_error("invalid_request", status: :unprocessable_content)
        end

        attr_reader :current_device

        # User-facing text the app shows verbatim (proposal Behavior Rules)
        ERROR_MESSAGES = {
          "unauthorised" => "Please sign in again.",
          "not_found" => "You no longer have access to this item.",
          "update_required" => "Please update CapHive to continue.",
          "invalid_request" => "Something went wrong. Please try again.",
          "invalid_credentials" => "Incorrect email or password.",
          "not_investor" => "This app is for investors. Please use the CapHive website.",
          "finish_2fa_setup" => "Finish setting up two-factor authentication on the CapHive website, then sign in here.",
          "code_undeliverable" => "We couldn't send your code. Please contact your fund manager to reset two-factor authentication.",
          "invalid_code" => "Code is incorrect or expired. Please try again.",
          "too_many_attempts" => "Too many failed attempts. Please sign in again.",
          "challenge_expired" => "Your sign-in timed out. Please sign in again.",
          "challenge_spent" => "Please sign in again.",
          "rate_limited" => "Please wait a moment before requesting another code.",
          "invalid_path" => "This page can't be opened.",
          "handoff_unavailable" => "This page can't be opened from the app right now. Please use the CapHive website."
        }.freeze

        def self.min_app_version
          Rails.application.credentials.dig(:mobile, :min_app_version).presence ||
            ENV["MOBILE_MIN_APP_VERSION"].presence || DEFAULT_MIN_APP_VERSION
        end

        def current_user
          current_device&.user
        end

        private

        # X7, X15, X5 — only the current token of a live device, owned by an active user
        def authenticate_mobile_device!
          # Resolved against the primary: a token minted a moment ago must not be checked against
          # a replica that has not caught up (same reasoning as Api::V1::Mail::BaseController)
          @current_device = ActiveRecord::Base.connected_to(role: :writing) { MobileDevice.authenticate(bearer_token) }
          render_error("unauthorised", status: :unauthorized) if @current_device.nil?
        end

        def bearer_token
          request.authorization.to_s[/\ABearer\s+(.+)\z/, 1]
        end

        # X9 — an app older than the region's minimum is told to update (HTTP 426)
        def require_app_version!
          version = request.headers["X-App-Version"].to_s
          return if version.blank? || Gem::Version.new(version) >= Gem::Version.new(self.class.min_app_version)

          render_error("update_required", status: :upgrade_required)
        rescue ArgumentError
          render_error("update_required", status: :upgrade_required)
        end

        # Endpoints that only touch the caller's own device or notifications authorise explicitly
        def skip_authorization_check?
          false
        end

        def page
          [params[:page].to_i, 1].max
        end

        # Fetches one more row than a page holds, so next_page is known without a COUNT(*)
        # on the large tables (CLAUDE.md large-table hygiene)
        def paginate(relation)
          rows = relation.limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
          [rows.first(PER_PAGE), rows.size > PER_PAGE ? page + 1 : nil]
        end

        def render_error(code, status:, **extra)
          render json: { error: code, message: ERROR_MESSAGES[code] }.merge(extra).compact, status:
        end
      end
    end
  end
end
