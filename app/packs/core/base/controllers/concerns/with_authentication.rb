module WithAuthentication
  extend ActiveSupport::Concern

  included do
    after_action :verify_authorized, except: %i[index search bulk_actions], unless: :devise_controller?
    after_action :verify_policy_scoped, only: [:index]

    before_action :set_current_entity
    before_action :switch_advisor, if: proc { |controller| controller.current_user&.has_cached_role?(:investor_advisor) && controller.params[:investor_advisor_id].present? }
    before_action :authenticate_user!, unless: :devise_controller?
    before_action :configure_permitted_parameters, if: :devise_controller?

    rescue_from Pundit::NotAuthorizedError, with: :deny_access
    rescue_from ActiveRecord::RecordNotFound, with: :deny_access
    rescue_from ActionController::RoutingError, with: :deny_access

    rescue_from ActionController::InvalidAuthenticityToken do |_exception|
      redirect_path = request.referer || root_path
      redirect_to redirect_path, alert: "Please refresh screen and retry"
    end
  end

  def authenticate_user!
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
  def deny_access
    if request.headers['Authorization'].present?
      render json: { error: "Access Denied" }, status: :forbidden
    else
      redirect_to root_path, alert: "Access Denied"
    end
  end

  def prepare_exception_notifier
    request.env["exception_notifier.exception_data"] = {
      current_user:
    }
  end

  def after_sign_out_path_for(_resource_or_scope)
    request.referer || root_path
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || root_path
  end

  def set_current_entity
    @current_entity = nil

    # Check if subdomain is present in the request
    @current_entity = Entity.where(sub_domain: request.subdomain).load_async.first if request.subdomain.present?

    # Check if subdomain parameter is present
    @current_entity = Entity.where(sub_domain: params[:sub_domain]).load_async.first if params[:sub_domain].present?

    # Check if the current entity exists and redirect accordingly
    if @current_entity.present? && (request.subdomain.blank? || %w[app dev].include?(request.subdomain))
      # Redirect to the path with subdomain in the parameter
      redirect_to "#{request.protocol}#{@current_entity.sub_domain}.#{ENV.fetch('BASE_DOMAIN', nil)}#{request.path}?#{request.query_string}", allow_other_host: true
    end
  end

  # This is called by the audited get see config/initializers/audited.rb For support staff that login as a user, we need to return the support user. This is so that any changes made will be logged under the support user and not the user they are importsonating
  def current_user_or_support_user
    current_user && current_user.support_user_id.present? ? current_user.support_user : current_user
  end
end
