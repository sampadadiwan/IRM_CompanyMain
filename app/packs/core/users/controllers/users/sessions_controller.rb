module Users
  class SessionsController < Devise::SessionsController
    # Mode dispatch is shared with the magic-link path in UsersController so a new
    # delivery mode cannot be wired into one entry point and not the other.
    include TwoFactorDispatch

    # Shown when an sms-mode user cannot be sent a code. Deliberately does not say why:
    # whether a number is textable is not something an unauthenticated caller should be
    # able to probe. SMS mode has no backup codes, so an administrator is the only route.
    SMS_UNDELIVERABLE_MESSAGE = "We can't send a verification code to your phone right now. " \
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

      if two_factor_path == :sms_undeliverable
        sign_out(resource)
        redirect_to new_session_path(User), alert: SMS_UNDELIVERABLE_MESSAGE
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
        redirect_to after_sign_in_path_for(resource)
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def destroy
      reset_session
      super
    end
  end
end
