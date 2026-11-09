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

        # M11 — the wrong-code kinds of MobileSignIn.verify: recorded as two_factor.code_failed, not as a sign-in failure
        CODE_FAILURE_KINDS = %i[invalid_code too_many_attempts locked].freeze

        # POST /api/mobile/v1/session — H1, H2, X1, X3, X4, E4
        def create
          result = MobileSignIn.call(email: params.require(:email), password: params.require(:password),
                                     device: device_params)
          render_result(result)
          # M11 S1e / H5 / E9 — after the answer, never changing it
          record_sign_in(result, door: "mobile", email: params[:email])
        end

        # POST /api/mobile/v1/session/verify — H1, E1, E2, X2
        def verify
          result = MobileSignIn.verify(challenge: params.require(:challenge), code: params.require(:code),
                                       device: device_params)
          render_result(result)
          # M11 S1e / T1 — a wrong code names the account (MobileSignIn::Result#user)
          record_sign_in(result, door: "mobile")
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
          result = MobileSignIn.cross_site(token: params.require(:token), device: device_params)
          render_result(result)
          # M11 S1h — the app's region switch
          record_sign_in(result, door: "cross_region")
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
          # M11 K2 — the phone signed itself out
          SecurityEvents.record("mobile_device.revoked", user: current_device.user, door: "mobile",
                                                         details: { name: current_device.name, reason: "app_sign_out" })
          head :no_content
        end

        private

        # M11 S1e / T1 — one event per answer: a session is a sign-in; a challenge is not yet anything (D4); a
        # wrong code is a two-factor failure; anything else is a refused sign-in with MobileSignIn's kind as
        # the reason. The typed email is kept only as a digest when no account is named.
        def record_sign_in(result, door:, email: nil)
          case result.kind
          when :session
            SecurityEvents.record("sign_in.succeeded", user: result.device.user, door:)
          when :challenge
            nil
          else
            if result.user && CODE_FAILURE_KINDS.include?(result.kind)
              attempt = TwoFactorVerifier::MAX_ATTEMPTS - result.attempts_left.to_i
              SecurityEvents.record("two_factor.code_failed", user: result.user, door:, outcome: :failure,
                                                              details: { attempt:, challenge_ended: result.kind != :invalid_code })
            else
              SecurityEvents.record("sign_in.failed", door:, outcome: :failure, actor: nil, email: email.to_s.presence,
                                                      details: { reason: result.kind.to_s })
            end
          end
        rescue StandardError => e
          # The answer is already rendered; recording must not change it
          Rails.logger.warn("[security_event] mobile_hook_failed #{e.class}")
        end

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
