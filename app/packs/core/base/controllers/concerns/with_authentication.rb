module WithAuthentication
  extend ActiveSupport::Concern

  included do
    after_action :verify_authorized, except: %i[index search bulk_actions], unless: :devise_controller?
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
      # Ensure that we always use the jbuilder and not the DataTable json (thats for UI only)
      params.merge(jbuilder: true)
    else
      # Authenticate using normal devise authentication using UI
      super
      # setup support_user_id if it is present
      current_user.support_user_id = session[:support_user_id] if current_user
    end
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

  def verify_authenticity_token
    if ENV['VULN_SCAN'] == "true"
      false if controller_name == "sessions"
    elsif request.headers['Authorization'].blank? && ENV['SKIP_AUTHENTICITY_TOKEN'] != "true"
      super
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name phone role entity_id whatsapp_enabled dept call_code])
  end

  private

  # Define the method to handle the error
  def deny_access(exception = nil)
    if request.headers['Authorization'].present?
      render json: { error: "Access Denied" }, status: :forbidden
    elsif request.headers['Turbo-Frame'].present?
      frame_id = ERB::Util.html_escape(request.headers['Turbo-Frame'])
      render html: "<turbo-frame id='#{frame_id}'><div class='alert alert-danger mb-0'>#{access_denied_message(exception)}</div></turbo-frame>".html_safe,
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
  # Names are HTML-escaped: layouts/_alerts.html.erb renders flashes with html_safe, and entity
  # names are admin-editable.
  # Worked examples H8, E17, E18, X9, X11 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
  def access_denied_message(exception, with_button: false)
    default = "Access Denied"
    return default unless exception.is_a?(Pundit::NotAuthorizedError) && current_user&.has_cached_role?(:investor_advisor)

    record = exception.record
    return default unless record.is_a?(ApplicationRecord) && exception.query.present?

    policy_class = exception.policy&.class || Pundit::PolicyFinder.new(record).policy!
    allowed = ->(persona) { persona.present? && policy_class.new(persona, record).public_send(exception.query) }
    where_now = current_user.investor_advisor? ? "you are currently switched into #{ERB::Util.html_escape(current_user.entity.name)}. " : ""

    # 1. Their own investment, while switched away (home_persona is nil when at home).
    return "#{default}: #{where_now}Switch your persona to Self to view this." if allowed.call(current_user.home_persona)

    # 2. A company they advise.
    grant = advisor_grant_that_can_see(record) { |candidate| allowed.call(current_user.switched_persona(candidate)) }
    return default unless grant

    name = ERB::Util.html_escape(grant.entity.name)
    message = "#{default}: #{where_now}You can view this as an advisor for #{name}. Switch your persona to #{name} to view it."
    with_button ? "#{message} #{switch_persona_button(grant)}" : message
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

  # The persona dropdown's own endpoint (POST /investor_advisors/switch with id), plus return_to so
  # the advisor lands back on the page they were denied. GET requests only: a denied form
  # submission has nothing safe to return to.
  def switch_persona_button(grant)
    return "" unless request.get?

    helpers.button_to("Switch to #{grant.entity.name}", switch_investor_advisors_path,
                      params: { id: grant.id, return_to: request.fullpath }, method: :post,
                      form: { class: "d-inline ms-2", data: { turbo: false } },
                      class: "btn btn-sm btn-light rounded-pill px-3")
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
        @current_entity = Entity.where(sub_domain: request.subdomain).load_async.first
      end
      # Check if subdomain parameter is present, sometimes this is sent from an email link
      @current_entity = Entity.where(sub_domain: params[:sub_domain].strip).load_async.first if params[:sub_domain].present?
    else
      our_domain = false
      # This is the case where a tenant has mapped thier own domain to their microsite. Ex app.tenant1.com -> tenant1.caphive.com
      @current_entity = Entity.where(domain: request.domain).load_async.first
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
