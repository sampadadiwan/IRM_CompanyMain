module Users
  class PasswordsController < Devise::PasswordsController
    skip_before_action :verify_authenticity_token, only: %i[create]
    skip_before_action :require_no_authentication,
                       :assert_reset_token_passed,
                       only: %i[edit update]

    protected

    # M3-H / M3-1 — Devise signs the user in straight after a successful reset. For a two-factor
    # user that sign-in would skip the code entirely (the emailed link alone would be a full login),
    # so they get Devise's "password changed" notice and the sign-in page instead, where the
    # password login sends them through TwoFactorDispatch like any other sign-in.
    # Devise's after_resetting_password_path_for reads this same method, so the redirect follows.
    def sign_in_after_reset_password?
      # Devise's own setting first, then the two-factor carve-out
      super && !resource.two_factor_enabled?
    end

    private

    def user_params
      params.expect(user: %i[password password_confirmation reset_password_token])
    end
  end
end
