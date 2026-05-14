module Users
  class SessionsController < Devise::SessionsController
    def create
      super do |user|
        user.update(session_token: SecureRandom.hex(64)) # Rotate session token
        cookies[:session_token] = { value: user.session_token, httponly: true, secure: !Rails.env.local? }
      end
    end

    def destroy
      reset_session # Ensures session is completely cleared
      super
    end
  end
end
