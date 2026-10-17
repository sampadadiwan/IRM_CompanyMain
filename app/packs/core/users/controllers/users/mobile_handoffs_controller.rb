module Users
  # GET /users/mobile_handoff?token=&path= — where the LP mobile app's one-time hand-off link
  # lands (lp-mobile-app design card ⑦). Verifies the credential, signs the user in on the
  # website exactly as a password login does, and redirects to the requested page. Any failure —
  # reused (X12), expired (X13), tampered, unsafe path — lands on the website sign-in page.
  #
  # The page itself still applies its own Pundit checks, so a link to a record the user may not
  # see shows the website's usual access-denied (E36).
  class MobileHandoffsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :set_current_entity, raise: false
    skip_after_action :verify_authorized

    def show
      path = params[:path].to_s
      user = ActiveRecord::Base.connected_to(role: :writing) do
        result = CrossSiteLink.new.verify(params[:token], purpose: Api::Mobile::V1::WebHandoffsController::PURPOSE,
                                                          site: SiteRegistry.current_code)
        next nil unless result.ok? && Api::Mobile::V1::WebHandoffsController.safe_path?(path)

        candidate = User.find_by(email: result.email)
        next nil unless candidate&.active_for_authentication?
        # Claimed last, so a link refused for any other reason is not also burned (as cross_site_login)
        next nil unless CrossSiteLink::Nonce.claim(params[:token])

        candidate
      end

      return redirect_to(new_user_session_path, alert: "This link has expired. Please open it again from the app.") if user.nil?

      # A GET runs on the reader, but sign_in writes (Devise's trackable / failed_attempts reset),
      # so it is pinned to the primary — as UsersController#cross_site_login does
      ActiveRecord::Base.connected_to(role: :writing) do
        sign_in(user)
        # Same session cookie a password login sets (Users::SessionsController#create)
        user.update(session_token: SecureRandom.hex(64))
      end
      cookies[:session_token] = { value: user.session_token, httponly: true, secure: !Rails.env.local? }
      redirect_to path
    end
  end
end
