module Users
  # devise-api's bearer-token endpoints (/users/tokens/*), with the two-factor gap closed.
  #
  # devise-api's own sign_in checks only the password, and ApplicationController accepts any
  # devise-api token on every JSON endpoint (WithAuthentication#authenticate_user!). So a user who
  # had two-factor switched on could skip the code entirely by asking this endpoint for a token.
  # Now a correct password for a two-factor user is refused here, and such a user's tokens can be
  # minted only by the LP mobile app's sign-in, after the code is verified (MobileSignIn).
  # Users without two-factor are unaffected.
  #
  # openspec/changes/lp-mobile-app — design decision 3, worked example X7.
  class TokensController < Devise::Api::TokensController
    before_action :refuse_phone_token_refresh, :refuse_api_token_refresh, :refuse_unbound_two_factor_refresh, only: :refresh

    def sign_in
      user = resource_class.find_for_authentication(email: sign_in_params[:email].to_s.strip.downcase)
      # Only after the password is proven, so the answer never reveals whether an account has
      # two-factor on; a wrong password still takes devise-api's normal path (and lockout count).
      # A locked account takes devise-api's normal path, so this never confirms a password for it
      return render_two_factor_required if user&.two_factor_enabled? && !user.access_locked? && user.valid_password?(sign_in_params[:password].to_s)

      super
    end

    private

    # A phone's token is refreshed only by the app (POST /api/mobile/v1/session/refresh), which keeps
    # the device pointing at its current token. Refreshing it here would leave the phone holding a
    # revoked token and mint one that is bound to no device.
    def refuse_phone_token_refresh
      token = current_devise_api_refresh_token
      return if token.nil? || !MobileDevice.exists?(devise_api_token_id: token.id)

      render json: { error: "use_mobile_refresh", error_description: ["Refresh this token from the CapHive app."] },
             status: :forbidden
    end

    # X21: a Profile › API tokens token lives its 90 days and is never refreshed — a new one is made
    # from the website, which re-proves the user's sign-in (funds-json-api-hardening card ②)
    def refuse_api_token_refresh
      token = current_devise_api_refresh_token
      return if token.nil? || !ApiToken.exists?(devise_api_token_id: token.id)

      render json: { error: "use_website_token", error_description: ["Make a new token from Profile › API tokens on the CapHive website."] },
             status: :forbidden
    end

    # A two-factor user's (non-phone) token is never refreshed here: such tokens can only exist
    # from before this check, and the user must sign in again through a code.
    def refuse_unbound_two_factor_refresh
      token = current_devise_api_refresh_token
      return if token.nil? || !token.resource_owner.try(:two_factor_enabled?)

      render_two_factor_required
    end

    def render_two_factor_required
      render json: { error: "two_factor_required",
                     error_description: ["Two-factor authentication is on for this account. Sign in with the CapHive website or app, which asks for your code."] },
             status: :forbidden
    end
  end
end
