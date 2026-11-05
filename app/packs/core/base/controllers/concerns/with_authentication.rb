module WithAuthentication
  extend ActiveSupport::Concern

  included do
    # H6 — bulk_actions is no longer exempt: WithBulkActions#bulk_actions authorizes :bulk_actions? first
    after_action :verify_authorized, except: %i[index search], unless: :devise_controller?
    after_action :verify_policy_scoped, only: [:index]

    before_action :set_current_entity
    # Finding 6: switch_advisor must only fire on POST requests.
    # This prevents state mutation on GET requests, which could be exploited
    # via phishing links or open redirects to silently switch an advisor's entity.
    before_action :switch_advisor, if: proc { |controller| controller.request.post? && controller.current_user&.has_cached_role?(:investor_advisor) && controller.params[:investor_advisor_id].present? }
    before_action :authenticate_user!, unless: :devise_controller?
    # After authenticate_user!, so current_user is resolved by the time we read it.
    before_action :set_current_user
    before_action :configure_permitted_parameters, if: :devise_controller?

    rescue_from Pundit::NotAuthorizedError, with: :deny_access
    rescue_from ActiveRecord::RecordNotFound, with: :deny_access
    rescue_from ActionController::RoutingError, with: :deny_access

    rescue_from ActionController::InvalidAuthenticityToken do |_exception|
      redirect_path = request.referer || root_path
      redirect_to redirect_path, alert: "Please refresh screen and retry"
    end
  end

  # opts is unused directly here, but must be accepted: Devise's
  # RegistrationsController#authenticate_scope! (used to guard edit/update/
  # destroy on a user's own account) calls authenticate_user!(force: true) —
  # a 0-arg override raises ArgumentError the moment anyone hits
  # /users/edit (or updates/deletes their own account). Bare `super` below
  # forwards opts on to Devise's own authenticate_user! automatically.
  def authenticate_user!(opts = {})
    if request.headers['Authorization'].present?
      authenticate_devise_api_token!
      # set the current user to the user that is logged in
      @current_user = current_devise_api_user
      # M4-1 / M4-2 / N6 — checked at use: a deactivated user's token stops at once, including the
      # users of a deactivated firm, whom EntityDeactivationJob flips with update_all (no callbacks,
      # so nothing revoked their tokens). The `active` column, not active_for_authentication?, so a
      # short Devise lockout does not break a user's integrations.
      if !performed? && @current_user && !@current_user.active?
        render json: { error: "account_deactivated", error_description: ["This account has been deactivated."] },
               status: :unauthorized
        return
      end
      # E11: a Profile › API tokens token records when it was last used (a phone's token has no row)
      ApiToken.find_by(devise_api_token_id: current_devise_api_token.id)&.touch_last_used! if current_devise_api_token && !performed?
    else
      # Authenticate using normal devise authentication using UI
      super
      # setup support_user_id if it is present
      current_user.support_user_id = session[:support_user_id] if current_user
    end
  end

  # A bearer-token request (the LP mobile app or another API client), as opposed to the website
  def api_request?
    request.headers['Authorization'].present?
  end

  def switch_advisor
    if params[:investor_advisor_id].present?
      # Switch to the advisor for the given investor
      Rails.logger.debug { "Switching to advisor for investor ID: #{params[:investor_advisor_id]}" }
      @investor_advisor = InvestorAdvisor.find(params[:investor_advisor_id])
      authorize(@investor_advisor, :switch?)
      ActiveRecord::Base.connected_to(role: :writing) do
        @investor_advisor.switch(current_user)
      end
    end
  end

  # L4-H / L4-1 — CSRF is verified for every cookie request. Bearer-token requests carry no cookie
  # to forge, so they skip it as before. SKIP_AUTHENTICITY_TOKEN is honoured in development only
  # (CsrfSwitches, config/initializers/csrf_switches.rb, which also refuses it at boot in
  # production/staging), and VULN_SCAN no longer switches CSRF off at all.
  def verify_authenticity_token
    # Bearer-token API requests: no session cookie, nothing to forge
    return if request.headers['Authorization'].present?
    # Local ngrok development only
    return if CsrfSwitches.skip_verification?

    super
  end

  protected

  def configure_permitted_parameters
    # C6 step 3 — no `role` (users have no such attribute). entity_id stays permitted for the super
    # user only in effect: Users::RegistrationsController#ensure_entity overwrites it with the
    # creator's own firm for everyone else (C6-X2).
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name phone entity_id whatsapp_enabled dept call_code])
  end

  private

  # Define the method to handle the error
  def deny_access(exception = nil)
    if request.headers['Authorization'].present?
      render json: { error: "Access Denied" }, status: :forbidden
    elsif request.headers['Turbo-Frame'].present?
      frame_id = ERB::Util.html_escape(request.headers['Turbo-Frame'])
      # The message is plain text (it names an entity, which is admin-editable): escape it here, where
      # it is put into HTML by hand.
      message = ERB::Util.html_escape(access_denied_message(exception))
      render html: "<turbo-frame id='#{frame_id}'><div class='alert alert-danger mb-0'>#{message}</div></turbo-frame>".html_safe,
             status: :forbidden
    else
      redirect_to root_path, alert: access_denied_message(exception, with_button: true)
    end
  end

  # Turns a bare "Access Denied" into "switch persona" guidance for a user holding the
  # investor_advisor role, when - and only when - a persona switch they can actually make would let
  # them see the denied record:
  #   1. Switched into a client, opening their OWN investment (e.g. a document notification - see
  #      Investor#visible_from_home_entity?): "Switch your persona to Self".
  #   2. Opening a record of a company they advise (a client's remittance from a notice that reached
  #      them at home, or a page in a fund company they are a Fund Advisor for): name that company,
  #      plus a button that switches and returns here (with_button, full-page denials only).
  # Each check re-runs the SAME policy query that denied the record against an in-memory persona
  # (User#home_persona / User#switched_persona) that mirrors exactly what Revert / the persona
  # dropdown would do, so the hint can never point at a switch that would still be denied. Nothing
  # is said when no switch helps, so the message never reveals that a record exists.
  # Cheap: runs only on the deny path, against at most two candidate grants.
  # Returns PLAIN TEXT. layouts/_alerts.html.erb escapes every flash (stored_and_reflected_xss.feature,
  # XSS-6), so names are not pre-escaped here — that would show "Smith &amp; Co". The switch button is
  # not part of the text any more: with_button stores what the button needs in flash[:switch_persona]
  # and the alerts partial draws it (see switch_persona_flash).
  # Worked examples H8, E17, E18, X9, X11 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
  def access_denied_message(exception, with_button: false)
    default = "Access Denied"
    return default unless exception.is_a?(Pundit::NotAuthorizedError) && current_user&.has_cached_role?(:investor_advisor)

    record = exception.record
    return default unless record.is_a?(ApplicationRecord) && exception.query.present?

    policy_class = exception.policy&.class || Pundit::PolicyFinder.new(record).policy!
    allowed = ->(persona) { persona.present? && policy_class.new(persona, record).public_send(exception.query) }
    where_now = current_user.investor_advisor? ? "you are currently switched into #{current_user.entity.name}. " : ""

    # 1. Their own investment, while switched away (home_persona is nil when at home).
    return "#{default}: #{where_now}Switch your persona to Self to view this." if allowed.call(current_user.home_persona)

    # 2. A company they advise.
    grant = advisor_grant_that_can_see(record) { |candidate| allowed.call(current_user.switched_persona(candidate)) }
    return default unless grant

    name = grant.entity.name
    # The button that switches and returns here, drawn by layouts/_alerts.html.erb from this flash
    flash[:switch_persona] = switch_persona_flash(grant) if with_button && request.get?
    "#{default}: #{where_now}You can view this as an advisor for #{name}. Switch your persona to #{name} to view it."
  rescue StandardError => e
    Rails.logger.warn { "access_denied_message: #{e.class}: #{e.message}" }
    default
  end

  # The advisor's grant whose switch would let them see `record`, or nil. Candidates are only the
  # grants on the record's investor entity (Investor Advisor kind - tried first, the more specific)
  # and on the record's own company (Fund Advisor kind), never the entity they are already in, and
  # only on active entities - the same set the persona dropdown offers.
  def advisor_grant_that_can_see(record, &)
    investor_entity_id = begin
      record.investor&.investor_entity_id if record.respond_to?(:investor)
    rescue ArgumentError
      nil
    end
    candidate_entity_ids = [investor_entity_id, record.try(:entity_id)].compact.uniq - [current_user.entity_id]
    return nil if candidate_entity_ids.empty?

    grants = InvestorAdvisor.joins(:entity).where(user_id: current_user.id, entity_id: candidate_entity_ids)
                            .where(entities: { active: true }).includes(:entity).to_a
    # Keep the candidates' priority order, not the database's.
    grants.sort_by { |g| candidate_entity_ids.index(g.entity_id) }.find(&)
  end

  # What the Access Denied alert's "Switch to <client>" button needs, as plain data. The alerts partial
  # turns it into the persona dropdown's own form (POST /investor_advisors/switch with id), plus
  # return_to so the advisor lands back on the page they were denied. GET requests only (checked by
  # the caller): a denied form submission has nothing safe to return to.
  # It used to be a button_to string appended to the flash text, which only worked while the alerts
  # partial printed flashes raw — and that let any name in any flash run as script.
  def switch_persona_flash(grant)
    { "grant_id" => grant.id, "label" => "Switch to #{grant.entity.name}", "return_to" => request.fullpath }
  end

  # The developer error email for a failing page carries ErrorReportContext.for_request under
  # data[:report]: who, switched into which entity, impersonated by whom, roles, request id.
  # It used to carry a raw dump of current_user, which named the user but none of that.
  # Lazy: nothing is looked up unless this request actually fails and the email is rendered,
  # and what it shows is the state at that moment (after a persona switch or login-as).
  def prepare_exception_notifier
    request.env["exception_notifier.exception_data"] = {
      report: ErrorReportContext::Lazy.new { ErrorReportContext.for_request(self) }
    }
  end

  def after_sign_out_path_for(_resource_or_scope)
    request.referer || root_path
  end

  # @param resource [User] the Devise resource that just signed in
  # @return [String] path to redirect to after sign-in
  # @note Checks for an OAuth return cookie first (set by Doorkeeper's resource_owner_authenticator
  #   before redirecting to Devise login). Cookie survives Devise session fixation reset; session-based
  #   stored_location_for does not.
  def after_sign_in_path_for(resource)
    oauth_return = cookies.delete(:oauth_return_to)
    oauth_return || stored_location_for(resource) || root_path
  end

  # Resolves the current entity (tenant) from the request subdomain or custom domain.
  # Skips for OAuth and ngrok routes where subdomain-based tenant resolution is not applicable.
  def set_current_entity
    return if request.path.start_with?("/oauth")

    @current_entity = nil

    Rails.logger.debug { "domain = #{request.domain}, sub_domain = #{request.subdomain}" }
    # Check is we are on caphive domain
    if request.domain == ENV["BASE_DOMAIN"]
      our_domain = true

      if %w[app dev].exclude?(request.subdomain) && request.subdomain.present?
        # Check if subdomain is present in the request and is not app or dev the default ones
        # Plain .first (no load_async) so the query is ORDER BY name LIMIT 1 - same row, without loading every match
        @current_entity = Entity.where(sub_domain: request.subdomain).first
      end
      # Check if subdomain parameter is present, sometimes this is sent from an email link
      @current_entity = Entity.where(sub_domain: params[:sub_domain].strip).first if params[:sub_domain].present?
    else
      our_domain = false
      # This is the case where a tenant has mapped thier own domain to their microsite. Ex app.tenant1.com -> tenant1.caphive.com
      # Runs on every custom-domain request; index_entities_on_domain keeps it off a full table scan
      @current_entity = Entity.where(domain: request.domain).first
    end

    # Check if we are on our domain and  current entity exists and we have a valid tenant_sub_domain, the redirect to the microsite of the tenant accordingly
    if our_domain && @current_entity.present? && @current_entity.sub_domain.present? && request.subdomain.blank?
      # Redirect to the path with tenant_sub_domain in the parameter
      redirect_to "#{request.protocol}#{@current_entity.sub_domain}.#{ENV.fetch('BASE_DOMAIN', nil)}#{request.path}?#{request.query_string}", allow_other_host: true
    end
  end

  # Publishes the acting user as ambient state so background jobs enqueued during
  # this request can be attributed to them (ApplicationJob reads Current.user at
  # enqueue time). Audits written *during* the request do not depend on this —
  # Audited::Sweeper reads current_user_or_support_user directly — so this is
  # deliberately the same value, keeping the two paths from disagreeing about who
  # acted when support staff are impersonating.
  def set_current_user
    Current.user = current_user_or_support_user
  end

  # This is called by the audited get see config/initializers/audited.rb For support staff that login as a user, we need to return the support user. This is so that any changes made will be logged under the support user and not the user they are importsonating
  def current_user_or_support_user
    current_user && current_user.support_user_id.present? ? current_user.support_user : current_user
  end
end
