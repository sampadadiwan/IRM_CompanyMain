# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # Phone sign-in: password, then (when two-factor is on) a code, then a device session.
      # The rules are MobileSignIn's / TwoFactorVerifier's; this controller maps each outcome to a
      # status code and the message the app shows (design card ②, LLD "Controllers").
      class SessionsController < BaseController
        skip_before_action :authenticate_mobile_device!, except: :destroy
        skip_after_action :verify_authorized, except: :destroy

        # POST /api/mobile/v1/session — H1, H2, X1, X3, X4, E4
        def create
          result = MobileSignIn.call(email: params.require(:email), password: params.require(:password),
                                     device: device_params)
          render_result(result)
        end

        # POST /api/mobile/v1/session/verify — H1, E1, E2, X2
        def verify
          result = MobileSignIn.verify(challenge: params.require(:challenge), code: params.require(:code),
                                       device: device_params)
          render_result(result)
        end

        # POST /api/mobile/v1/session/resend — E3
        def resend
          case MobileSignIn.resend(challenge: params.require(:challenge))
          when :sent, :not_needed then head :no_content
          when :rate_limited then render_error("rate_limited", status: :too_many_requests)
          when :undeliverable then render_error("code_undeliverable", status: :service_unavailable)
          else render_error("challenge_expired", status: :unauthorized)
          end
        end

        # POST /api/mobile/v1/session/cross_site — region switch, step 2 (lp-mobile-multi-site MS-H3)
        def cross_site
          render_result(MobileSignIn.cross_site(token: params.require(:token), device: device_params))
        end

        # POST /api/mobile/v1/session/refresh — H3: rotates the token pair of a live device
        def refresh
          device = MobileDevice.for_refresh_token(params.require(:refresh_token))
          return render_error("unauthorised", status: :unauthorized) if device.nil? || !device.user.active_for_authentication?

          render json: token_json(device, device.refresh!), status: :created
        end

        # DELETE /api/mobile/v1/session — signs this phone out (proposal C4)
        def destroy
          authorize current_device, :destroy?
          current_device.revoke!(reason: "app_sign_out")
          head :no_content
        end

        private

        def device_params
          params.require(:device).permit(:install_id, :platform, :name, :app_version)
        end

        def render_result(result)
          case result.kind
          when :session then render json: token_json(result.device, result.token), status: :created
          when :challenge
            render json: { challenge: result.challenge, method: result.two_factor_method,
                           attempts_left: result.attempts_left }, status: :accepted
          when :invalid then render_error("invalid_credentials", status: :unauthorized)
          when :locked
            render json: { error: "locked", message: locked_message }, status: :locked
          when :not_investor then render_error("not_investor", status: :forbidden)
          when :finish_2fa_setup then render_error("finish_2fa_setup", status: :forbidden)
          when :undeliverable then render_error("code_undeliverable", status: :service_unavailable)
          when :invalid_code
            render_error("invalid_code", status: :unprocessable_content, attempts_left: result.attempts_left)
          when :too_many_attempts then render_error("too_many_attempts", status: :unauthorized)
          when :spent then render_error("challenge_spent", status: :unauthorized)
          when :handoff_invalid then render_error("region_switch_failed", status: :unauthorized)
          else render_error("challenge_expired", status: :unauthorized)
          end
        end

        # The website's lockout: Devise lockable, maximum_attempts failed passwords, unlocked after
        # unlock_in (X3)
        def locked_message
          minutes = (Devise.unlock_in / 60).to_i
          "Your account is locked. Please try again in #{minutes} #{'minute'.pluralize(minutes)}."
        end

        def token_json(device, token)
          { access_token: token.access_token, refresh_token: token.refresh_token,
            expires_in: token.expires_in, device_id: device.id }
        end
      end
    end
  end
end
