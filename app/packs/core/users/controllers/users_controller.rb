class UsersController < ApplicationController
  # Shared 2FA mode dispatch, also used by Users::SessionsController for password login.
  include TwoFactorDispatch

  before_action :authenticate_user!, except: %w[magic_link no_password_login welcome cross_site_login redirect_to_subdomain]
  # skip_before_action :verify_authenticity_token, only: %i[magic_link]

  skip_before_action :verify_authenticity_token, :authenticate_user!, only: %i[signature_progress whatsapp_webhook]
  skip_before_action :set_current_entity, only: %i[whatsapp_webhook]

  before_action :set_user, only: %w[show update destroy edit reset_two_factor]
  after_action :verify_authorized, except: %i[welcome index search reset_password accept_terms set_persona magic_link no_password_login whatsapp_webhook cross_site_login redirect_to_subdomain]

  def welcome; end

  def chat
    authorize(User)

    # chat_class = current_user.curr_role == "Investor" ? InvestorLlmChat : InvestorLlmChat
    chat_class = InvestorLlmChat
    @response = chat_class.new(user: current_user).query(params[:query])
  end

  def whatsapp_webhook
    WhatsappAgentJob.perform_later(params.to_json)

    render json: "Ok"
  end

  # GET /users or /users.json
  def index
    @bread_crumbs = { Users: users_path }
    authorize(User)
    @users = policy_scope(User).includes(:entity, :roles)
  end

  def search
    query = params[:query]
    if query.present?
      @users = UserIndex.filter(term: { entity_id: current_user.entity_id })
                        .query(simple_query_string: { fields: %i[first_name last_name email],
                                                      query:, default_operator: 'and' })

      render "index"
    else
      redirect_to users_path
    end
  end

  def magic_link
    # Security fix (Finding 3 — email enumeration): the original code returned a different
    # flash message depending on whether the email was registered:
    #   found     → "Login link sent, please check your mailbox."
    #   not found → "User not found. Please signup."
    # An unauthenticated attacker could probe this endpoint to determine which addresses are
    # in the system, especially because the per-email Rack::Attack throttle was broken for
    # this action (it read params['email'] but the form sends user[email]).
    #
    # Fix: the browser always receives the same response. For the not-found case we send a
    # "no account found" email to the submitted address instead of disclosing anything in the
    # HTTP response. A legitimate user who mistyped their address learns about it in their own
    # inbox; an attacker probing the endpoint gains no information from the HTTP response.
    email = params.dig(:user, :email).to_s.strip.downcase
    @user = User.find_by(email:)

    if @user
      # Security fix (Finding 7 — redirect_to phishing): do not forward params[:redirect_to]
      # into the magic link email. See the no_password_login action below for the full
      # rationale. The destination after login is handled server-side via session[:user_return_to].
      @user.send_magic_link(params[:current_entity_id])
    else
      UserMailer.with(email:).no_account_found.deliver_later
    end

    # Identical flash for both branches — no enumeration oracle.
    redirect_to new_session_path(User, display_status: true),
                notice: "If that address is registered, a login link is on its way."
  end

  # Generates a cross-site login link for the user and redirects to the target site
  # rubocop:disable Security/Eval
  def cross_site_link
    authorize current_user
    # Generate a short-lived token for the user's email, purpose: login
    site = params[:site].to_sym
    token = CrossSiteLink.new.generate(current_user.email, purpose: :login, expires_in: 30.seconds, site: site)

    # Route through redirect_to_subdomain so the target site can resolve the user's subdomain
    url = eval(ENV.fetch("SITES", nil))[site] + "/users/redirect_to_subdomain?token=#{token}"

    # Redirect the user to the cross-site login URL
    redirect_to url, allow_other_host: true
  end
  # rubocop:enable Security/Eval

  # Handles login via a cross-site link
  def cross_site_login
    # The request comes in as a GET request, but the sign_in method modifies state, so we need the writing role
    ActiveRecord::Base.connected_to(role: :writing) do
      # Verify the token and extract the payload (user email)
      site = ENV.fetch("CURRENT_SITE", nil).to_sym
      payload = CrossSiteLink.new.verify(params[:token], purpose: :login, site: site)
      # Find the user by email
      user = User.find_by!(email: payload[:email])
      # Sign in the user
      sign_in(user)
    end
    # Redirect to the root path after successful login
    redirect_to root_path
  rescue CrossSiteLink::VerificationError
    # Handle invalid or expired token
    render plain: "Invalid or expired link", status: :unauthorized
  end

  # Resolves the user's entity subdomain and redirects to the correct subdomain for cross-site login.
  # Falls back to "app" if the entity has no sub_domain set.
  def redirect_to_subdomain
    payload = CrossSiteLink.new.peek(params[:token])
    render(plain: "Invalid or expired link", status: :unauthorized) and return if payload.nil?

    user = User.find_by(email: payload[:email])
    render(plain: "User not found", status: :not_found) and return if user.nil?

    # Use the entity's sub_domain or fall back to "app"
    sub = user.entity&.sub_domain.presence || "app"

    # Replace whatever subdomain is in the current host with the user's subdomain
    host = request.host.sub(/\A[^.]+\./, "#{sub}.")
    url  = "#{request.protocol}#{host}/users/cross_site_login?token=#{params[:token]}"

    redirect_to url, allow_other_host: true
  end

  def no_password_login
    # Security fix (Finding 5): Capture the support user identity before any sign_in call
    # changes current_user. We need both the id (for the audit session) and the full object
    # (to run the allow_login_as check).
    support_user    = current_user&.has_cached_role?(:support) ? current_user : nil
    support_user_id = support_user&.id

    unless params[:signed_id]
      redirect_to new_session_path(User), notice: "Invalid login link"
      return
    end

    # Find user by signed id — see https://kukicola.io/posts/signed-urls-with-ruby/
    # SECURITY (finding M1): verify with the dedicated login purpose so ONLY tokens minted for
    # login (magic-link email / WhatsApp) are accepted — a User#signed_id created for any other
    # purpose can no longer be replayed here. Must match User::MAGIC_LINK_PURPOSE at the mints.
    @user = User.find_signed(params[:signed_id], purpose: User::MAGIC_LINK_PURPOSE)

    if @user.blank?
      redirect_to new_session_path(User), notice: "Invalid login link"
      return
    end

    # Security fix (Finding 5): SupportClientMapping#allow_login_as was never called in this
    # action, making the enable_user_login / user_emails whitelist completely unenforced. Any
    # user with the :support role could log in as any client user regardless of what the
    # administrator configured on the mapping. Now we look up the active mapping for this
    # support user and the target user's entity and reject the login if the support user's
    # email is not whitelisted (or if login delegation is disabled on the mapping entirely).
    if support_user.present?
      mapping = SupportClientMapping.find_by(
        user_id: support_user_id,
        entity_id: @user.entity_id,
        enabled: true
      )
      unless mapping&.allow_login_as(support_user.email)
        redirect_to root_path, alert: "Login delegation not permitted for this account."
        return
      end
    end

    # Security (Finding 7 follow-up): the link itself never carries a destination — see
    # User#send_magic_link — so anything in params[:redirect_to] was appended by whoever
    # is holding the URL. Accept it only as a same-origin path; an external host would
    # otherwise 500 on Rails' open-redirect guard after a successful code, and a
    # protocol-relative "//evil" must not slip through as a "path".
    return_to = local_path_or_nil(params[:redirect_to])

    ActiveRecord::Base.connected_to(role: :writing) do
      # Shared with the password-login path in Users::SessionsController — see
      # TwoFactorDispatch for why this branch is not written out twice. No sign_out
      # here: on the magic-link path the user was never signed in to begin with.
      two_factor_path = two_factor_challenge_path_for(@user)
      if two_factor_path == :undeliverable
        redirect_to new_session_path(User),
                    alert: Users::SessionsController::UNDELIVERABLE_MESSAGE
        return
      elsif two_factor_path
        # The link's own redirect_to only survives this request. Park it where
        # after_sign_in_path_for (used by TwoFactorController#complete_login) will find
        # it, so a 2FA user lands on the linked page rather than the dashboard.
        session[:user_return_to] = return_to if return_to
        redirect_to two_factor_path
        return
      end

      sign_in @user
      # Set support_user_id in session so the audit trail records who actually made changes.
      # See ApplicationController#current_user_or_support_user and config/initializers/audited.rb
      session[:support_user_id] = support_user_id if support_user_id.present?
    end

    redirect_to(return_to || session[:user_return_to].presence || root_path,
                notice: "Signed in successfully")
  end

  # POST /users/:id/login_as
  # Authenticated admin/support impersonation.
  #
  # SECURITY (finding H2): this replaces the old flow where the admin UI minted a signed_id
  # magic link (user.signed_id) pointing at no_password_login. That link was a bearer token —
  # anyone who obtained the URL while logged out could redeem it because no_password_login only
  # applied the allow_login_as whitelist when a support user was already in session. Here the
  # acting admin must be authenticated and pass UserPolicy#login_as?, so a leaked URL cannot be
  # replayed by an anonymous party. no_password_login is intentionally left unchanged and still
  # serves the email self-login magic link (which is legitimately redeemed while logged out).
  def login_as
    @user = User.find(params[:id])
    authorize @user, :login_as?

    # Capture the acting (support) user's id BEFORE sign_in swaps current_user, so the audit
    # trail attributes the impersonated actions to the real actor.
    support_user_id = current_user.id

    ActiveRecord::Base.connected_to(role: :writing) do
      # NOTE: we intentionally do NOT trigger the target's 2FA here. A support agent does not
      # have the client's OTP device, so requiring it would make impersonation impossible for
      # any 2FA-enabled client. The security gate for this flow is the acting agent's OWN
      # authenticated session plus UserPolicy#login_as? (role + allow_login_as whitelist), not
      # the target's second factor. (The email self-login flow in no_password_login still
      # enforces 2FA — it is the account owner logging into their own account.)
      sign_in @user
      # Record the real actor for the audit trail (see ApplicationController#current_user_or_support_user).
      session[:support_user_id] = support_user_id
    end

    redirect_to root_path, notice: "Signed in as #{@user.full_name}"
  end

  # POST /users/1/reset_two_factor
  #
  # Clears the user's two-factor METHOD (not the two-factor flag) so they pick a new one at
  # their next login. Two callers share this action:
  #   * the user themselves, from their own profile page — TwoFactorReset re-checks their
  #     password (params[:password]) and we sign them out immediately so they go straight
  #     to the mode-selection screen rather than sitting in a session whose second factor
  #     is half-configured;
  #   * a company admin / support user, from the target's user page — no password check
  #     (the acting admin's own session + UserPolicy#reset_two_factor? is the gate); the
  #     target's next login lands on mode selection via TwoFactorDispatch.
  # See docs/technical/two_factor_authentication.md, "Resetting the two-factor method".
  def reset_two_factor
    authorize @user, :reset_two_factor?

    result = TwoFactorReset.call(user: @user, actor: current_user,
                                 password: params[:password], message: params[:message])

    if result.success?
      if @user.id == current_user.id
        # Self-service: end the session now. Signing back in routes to select_mode
        # because two_factor_mode is nil (TwoFactorDispatch).
        sign_out current_user
        redirect_to new_user_session_path,
                    notice: "Your two-factor method has been reset. Sign in again to choose a new method."
      else
        redirect_to user_path(@user),
                    notice: "Two-factor method reset for #{@user.full_name}. They will choose a new method at their next sign-in."
      end
    else
      redirect_to user_path(@user), alert: result[:errors]
    end
  end

  # GET /users/1 or /users/1.json
  def show
    @bread_crumbs = { Users: users_path, "#{@user.full_name}": user_path(@user) }
    authorize @user
  end

  # GET /users/new
  def new
    @bread_crumbs = { Users: users_path, New: nil }
    @user = params[:user].present? ? User.new(user_params) : User.new
    @user.entity_id = current_user.entity_id
    @user.permissions ||= current_user.permissions
    @user.extended_permissions ||= current_user.extended_permissions
    authorize @user
    setup_custom_fields(@user)
  end

  # GET /users/1/edit
  def edit
    @bread_crumbs = { Users: users_path, "#{@user.full_name}": user_path(@user), Edit: nil }
    authorize @user
    setup_custom_fields(@user)
  end

  # PATCH/PUT /users/1 or /users/1.json
  def update
    authorize @user

    respond_to do |format|
      if @user.update(user_params)

        # Only touch roles when the roles field was actually submitted (it's only rendered for
        # company admins) and only a company admin may change them at all. Any role not in
        # User::UPDATABLE_ROLES (e.g. investor, support, investor_advisor, rm) is left untouched
        # regardless of what was submitted here.
        if current_user.has_cached_role?(:company_admin) && params[:user].key?(:role_name)
          submitted_roles = Array(user_params[:role_name])

          User::UPDATABLE_ROLES.each do |role|
            submitted_roles.include?(role) ? @user.add_role(role) : @user.remove_role(role)
          end
        end
        format.html { redirect_to user_url(@user), notice: "User was successfully updated." }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    authorize @user
    @user.destroy

    respond_to do |format|
      format.html { redirect_to users_url, notice: "User was successfully deleted." }
      format.json { head :no_content }
    end
  end

  def accept_terms
    current_user.accept_terms = true
    current_user.accepted_terms_on = Time.zone.now
    current_user.save

    # puts current_user.to_json

    redirect_to root_path
  end

  def set_persona
    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.set_persona(params[:user][:persona]) if params[:user].present? && params[:user][:persona].present?
    end
    redirect_to request.referer || root_path
  end

  # This is used to reset password only for system generated users on the first login
  def reset_password
    raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
    current_user.reset_password_token = hashed
    current_user.reset_password_sent_at = Time.now.utc
    current_user.save

    sign_out current_user

    redirect_to edit_user_password_path(reset_password_token: raw)
  end

  # reset_access_rights_cache action removed: cache no longer exists.
  # Policy checks use live DB queries; manual cache invalidation is not needed.

  private

  # A caller-supplied destination is honoured only when it is a path on this host: it
  # must start with a single "/" (so "//evil.example" and "/\\evil.example", which
  # browsers read as protocol-relative URLs, are refused) and carry no scheme.
  #
  # @return [String, nil]
  def local_path_or_nil(value)
    value = value.to_s.strip
    return nil if value.blank?
    return nil unless value.start_with?("/") && !value.start_with?("//", "/\\")

    value
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def user_params
    permitted = if current_user.has_cached_role?(:company_admin)
                  params.require(:user).permit(:first_name, :last_name, :email,
                                               :phone, :whatsapp_enabled, :two_factor_enabled, :signature, :call_code,
                                               :dept, :sale_notification, :enable_support, :tag_list, :entity_id,
                                               role_name: [], permissions: [], extended_permissions: [], properties: {}, preferences: {})
                else
                  params.require(:user).permit(:first_name, :last_name, :email,
                                               :phone, :whatsapp_enabled, :two_factor_enabled, :signature, :call_code,
                                               :dept, :sale_notification, :enable_support, :tag_list, properties: {})
                end

    permitted[:preferences] = sanitized_preferences if current_user.has_cached_role?(:company_admin) && params.dig(:user, :preferences, :dashboard).present?

    permitted
  end

  # Safely extracts dashboard preferences from params. Allows updating valid dashboard types
  # while preserving other existing preferences.
  def sanitized_preferences
    prefs = (@user.preferences || {}).deep_dup
    dashboard_prefs = prefs["dashboard"] || {}
    dashboard_params = params.dig(:user, :preferences, :dashboard)

    if dashboard_params.respond_to?(:each)
      dashboard_params.each do |dashboard_type, config|
        next unless DashboardWidget.dashboard_names.include?(dashboard_type)

        dashboard_prefs[dashboard_type] = { "sequence" => config[:sequence].to_s.strip }
      end
    end

    prefs.merge("dashboard" => dashboard_prefs)
  end
end
