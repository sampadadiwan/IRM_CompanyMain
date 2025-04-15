class ApplicationController < ActionController::Base
  layout 'modernize'

  include Pundit::Authorization

  after_action :verify_authorized, except: %i[index search bulk_actions], unless: :devise_controller?
  after_action :verify_policy_scoped, only: [:index]

  before_action :set_current_entity
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  # skip_after_action :verify_authorized, if: :mission_control_controller?
  # skip_after_action :verify_policy_scoped, if: :mission_control_controller?

  # def mission_control_controller?
  #   is_a?(::MissionControl::Jobs::ApplicationController)
  # end

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

  def verify_authenticity_token
    if ENV['VULN_SCAN'] == "true"
      false if controller_name == "sessions"
    elsif request.headers['Authorization'].blank? && ENV['SKIP_AUTHENTICITY_TOKEN'] != "true"
      super
    end
  end

  # This is a common action for all models which have filters. Bulk actions can be applied to filtered results. A Job "#{controller_name}BulkActionJob", needs to be defined, which will be passed the ids of the filtered results. and the bulk action to perform on them. Note that the controller must implement a fetch_rows method which returns the filtered results.
  def bulk_actions
    # Here we get a ransack search
    rows = fetch_rows

    # and a bulk action to perform on the results
    bulk_action_job = if params[:bulk_action_job_prefix].blank?
                        # The specific bulk action job is passed as a parameter
                        "#{params[:bulk_action_job_prefix]}_#{controller_name}_bulk_action_job".classify.constantize
                      else
                        # The Default bulk action job is the controller name suffixed with BulkActionJob
                        "#{controller_name}_bulk_action_job".classify.constantize
                      end

    bulk_action_job.perform_later(rows.pluck(:id), current_user.id, params[:bulk_action], params: params.to_unsafe_h)

    # and redirect back to the page we came from
    redirect_path = request.referer || root_path
    redirect_to redirect_path, notice: "Bulk Action started, please check back in a few mins."
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name phone role entity_id whatsapp_enabled dept call_code])
  end

  rescue_from Pundit::NotAuthorizedError, with: :deny_access
  rescue_from ActiveRecord::RecordNotFound, with: :deny_access
  rescue_from ActionController::RoutingError, with: :deny_access

  rescue_from ActionController::InvalidAuthenticityToken do |_exception|
    redirect_path = request.referer || root_path
    redirect_to redirect_path, alert: "Please refresh screen and retry"
  end

  before_action :prepare_exception_notifier

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

  def setup_custom_fields(model, type: nil, force_form_type: nil)
    # I a few cases we need to force the form type Ex SecondarySale, Offer, Interest
    form_type = force_form_type

    # If the form type is not forced, we will try to find the form type based on the type
    form_type ||= if type.present?
                    FormType.where(entity_id: model.entity_id, name: type).last
                  else
                    FormType.where(entity_id: model.entity_id, name: model.class.name).last
                  end

    # set the models form type
    model.form_type = form_type
  end

  def setup_doc_user(model)
    sym = model.class.name.underscore.to_sym
    if params[sym][:documents_attributes].present?
      params[sym][:documents_attributes].each_value do |doc_attribute|
        doc_attribute[:user_id] = current_user.id
        doc_attribute.merge!(entity_id: model.entity_id)
      end
    end

    # For some reason the code above does not work for new records
    # hack for now
    if model.new_record?
      model.documents.each do |doc|
        doc.user_id = current_user.id
      end
    end
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

  def with_owner_access(relation, raise_error: true)
    if params[:owner_id].present? && params[:owner_type].present?
      unless current_user.company_admin?
        # If owner is passed, check if user is authorized to view the owner
        @owner = params[:owner_type].constantize.find(params[:owner_id])
        authorize(@owner, :show?)
      end
      relation.where(owner_id: params[:owner_id], owner_type: params[:owner_type])
    elsif !current_user.company_admin? && raise_error
      # Raise AccessDenied if user is an employee and no owner is passed
      raise Pundit::NotAuthorizedError
    else
      relation
    end
  end

  def get_q_param(name)
    value = nil
    @q.conditions.each do |condition|
      #   # Check if the condition's attribute (name) is 'interest_id'
      value = condition.values.map(&:value).first if condition.attributes.map(&:name).include?(name.to_s)
    end
    value
  end


  # This method is used to perform a Ransack search on the model associated with the current controller,
  # apply policy scope, and optionally filter the results to include only records with snapshots.
  #
  # @return [ActiveRecord::Relation] The scoped query result after applying Ransack search, policy scope,
  #   and optional snapshot filtering.
  #
  # The method performs the following steps:
  # 1. Determines the model class associated with the current controller.
  # 2. Initializes a Ransack search object using the `params[:q]` query parameters.
  # 3. Applies the policy scope to the Ransack search result.
  # 4. If the `params[:snapshot]` parameter is present, further filters the results to include records with snapshots also.
  def ransack_with_snapshot
    # Get the current controllers model class
    model_class = controller_name.classify.constantize
    # Get the ransack search object
    @q = model_class.ransack(params[:q])
    # Create the scope for the model
    scope = policy_scope(@q.result)
    # If snapshot is present, we need to return records with_snapshots
    scope = scope.with_snapshots if params[:snapshot].present?
    scope
  end
end
