module Users
  class PasswordsController < Devise::PasswordsController
    skip_before_action :verify_authenticity_token, only: %i[create]
    skip_before_action :require_no_authentication,
                       :assert_reset_token_passed,
                       only: %i[edit update]

    # M11 A2 / E20 — Forgot password: Devise's paranoid answer is unchanged; the request is recorded against the
    # account when the email names one, else as a digest only
    def create
      super
      record_reset_request
    end

    # M11 S1d / H4 — a reset that signs the user straight in is a sign-in through the reset door (the
    # password.changed event comes from the user's after-commit, A1). A two-factor user is not signed in here
    # (sign_in_after_reset_password?), so nothing is recorded until their code passes.
    def update
      super
      SecurityEvents.record("sign_in.succeeded", user: resource, door: "password_reset") if resource.errors.empty? && user_signed_in?
    end

    protected

    # M3-H / M3-1 — Devise signs the user in straight after a successful reset. For a two-factor
    # user that sign-in would skip the code entirely (the emailed link alone would be a full login),
    # so they get Devise's "password changed" notice and the sign-in page instead, where the
    # password login sends them through TwoFactorDispatch like any other sign-in.
    # Devise's after_resetting_password_path_for reads this same method, so the redirect follows.
    def sign_in_after_reset_password?
      # Devise's own setting first, then the two-factor carve-out — which, since M8, also covers a
      # support / super user who must set two-factor up (E16)
      super && !resource.two_factor_applies?
    end

    private

    # A2 — the found account, or (unknown email, paranoid mode) the typed email for its digest only
    def record_reset_request
      if resource&.persisted?
        SecurityEvents.record("password.reset_requested", user: resource, door: "password_reset")
      else
        SecurityEvents.record("password.reset_requested", door: "password_reset", actor: nil,
                                                          email: params.dig(:user, :email).to_s)
      end
    rescue StandardError => e
      # A malformed form must not turn Devise's answer into an error page
      Rails.logger.warn("[security_event] reset_request_hook_failed #{e.class}")
    end

    def user_params
      params.expect(user: %i[password password_confirmation reset_password_token])
    end
  end
end
