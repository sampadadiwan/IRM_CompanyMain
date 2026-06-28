module Users
  class SessionsController < Devise::SessionsController
    def create
      self.resource = warden.authenticate!(auth_options)

      if resource.two_factor_enabled?
        if resource.two_factor_mode.nil?
          # Mode not yet chosen — send to selection screen before enrollment
          session[:otp_user_id] = resource.id
          sign_out(resource)
          redirect_to select_mode_two_factor_path
        elsif resource.whatsapp_mode?
          # WhatsApp mode — auto-send OTP before showing verification page
          session[:otp_user_id] = resource.id
          sign_out(resource)
          ActiveRecord::Base.connected_to(role: :writing) do
            resource.send_otp_via_whatsapp
          end
          session[:otp_whatsapp_sent_at] = Time.current.to_s
          redirect_to new_two_factor_path
        else
          # Authenticator mode — user reads code from their app
          session[:otp_user_id] = resource.id
          sign_out(resource)
          redirect_to new_two_factor_path
        end
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
