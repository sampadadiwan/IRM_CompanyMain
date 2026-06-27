class UsersController < ApplicationController
  before_action :authenticate_user!, except: %w[magic_link no_password_login welcome cross_site_login]
  # skip_before_action :verify_authenticity_token, only: %i[magic_link]

  skip_before_action :verify_authenticity_token, :authenticate_user!, only: %i[signature_progress whatsapp_webhook]
  skip_before_action :set_current_entity, only: %i[whatsapp_webhook]

  before_action :set_user, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[welcome index search reset_password accept_terms set_persona magic_link no_password_login whatsapp_webhook cross_site_login]

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

    # Build the target URL using the site param and the generated token
    url = eval(ENV.fetch("SITES", nil))[site] + "/users/cross_site_login?token=#{token}"

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
    @user = User.find_signed(params[:signed_id])

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

    ActiveRecord::Base.connected_to(role: :writing) do
      if @user.two_factor_enabled?
        if @user.otp_secret.blank?
          session[:otp_user_id] = @user.id
          redirect_to enroll_two_factor_path
          return
        else
          session[:otp_user_id] = @user.id
          redirect_to new_two_factor_path
          return
        end
      end

      sign_in @user
      # Set support_user_id in session so the audit trail records who actually made changes.
      # See ApplicationController#current_user_or_support_user and config/initializers/audited.rb
      session[:support_user_id] = support_user_id if support_user_id.present?
    end

    redirect_to(params[:redirect_to].presence || session[:user_return_to].presence || root_path,
                notice: "Signed in successfully")
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

        if current_user.has_cached_role?(:company_admin)
          User::UPDATABLE_ROLES.each do |role|
            user_params[:role_name].present? && user_params[:role_name].include?(role) ? @user.add_role(role) : @user.remove_role(role)
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
