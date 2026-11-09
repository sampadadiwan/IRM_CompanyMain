module Users
  class SessionsController < Devise::SessionsController
    # Mode dispatch is shared with the magic-link path in UsersController so a new
    # delivery mode cannot be wired into one entry point and not the other.
    include TwoFactorDispatch

    # Shown when a WhatsApp- or SMS-mode user cannot be sent a code. Deliberately does not
    # say why: whether a number is textable or on WhatsApp is not something an
    # unauthenticated caller should be able to probe. There are no backup codes, so an
    # administrator is the only route.
    UNDELIVERABLE_MESSAGE = "We can't send a verification code to your phone right now. " \
                            "Please contact your administrator.".freeze

    def new
      # A session-expired Turbo Frame fetch auto-follows Devise's redirect here and
      # renders this page once to check for a matching <turbo-frame> (see
      # turbo_frame_error_handler.js) — that render is thrown away, and with it the
      # flash Rails would otherwise sweep after being read. The frame fetch still
      # carries its Turbo-Frame header on the followed redirect, so `keep` only for
      # that throwaway render; the real full-page reload that follows (plain
      # navigation, no header) then sees the flash Devise originally set.
      flash.keep if request.headers["Turbo-Frame"].present?
      super
    end

    def create
      self.resource = warden.authenticate!(auth_options)

      two_factor_path = two_factor_challenge_path_for(resource)

      if two_factor_path == :undeliverable
        sign_out(resource)
        redirect_to new_session_path(User), alert: UNDELIVERABLE_MESSAGE
      elsif two_factor_path
        # The user is NOT signed in until they clear 2FA — only session[:otp_user_id]
        # carries them forward, which is what Users::TwoFactorController checks.
        sign_out(resource)
        redirect_to two_factor_path
      else
        # Standard login (no 2FA)
        sign_in(resource)
        resource.update(session_token: SecureRandom.hex(64))
        cookies[:session_token] = { value: resource.session_token, httponly: true, secure: !Rails.env.local? }
        set_flash_message!(:notice, :signed_in)
        # M11 S1a / H1 — a password-only sign-in is complete here (a two-factor user is recorded only once
        # the code passes, TwoFactorController — D4)
        SecurityEvents.record("sign_in.succeeded", user: resource, door: "web_password")
        redirect_to after_sign_in_path_for(resource)
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def destroy
      # M11 S3 / P2 — recorded before reset_session, which wipes support_user_id (H20)
      record_sign_out
      reset_session
      super
    end

    private

    # H20 — when CapHive support was signed in as this user, the end of that visit is recorded
    # (support.session_ended). H10 — a plain sign-out is NOT recorded (user decision 2026-11-09): it proves no
    # session ended (most end by timing out), needs no action, and only buried the rows that matter.
    def record_sign_out
      return unless current_user && session[:support_user_id].present?

      SecurityEvents.record("support.session_ended", user: current_user)
    end
  end
end
