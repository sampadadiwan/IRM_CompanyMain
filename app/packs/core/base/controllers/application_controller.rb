class ApplicationController < ActionController::Base
  layout 'modernize'

  include Pundit::Authorization

  after_action :verify_authorized, except: %i[index search bulk_actions], unless: :devise_controller?
  after_action :verify_policy_scoped, only: [:index]

  before_action :set_current_entity
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  before_action :set_locale

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

  def resolve_mailer_class(resource)
    base = resource.class.name
    base = "InvestorKyc" if %w[IndividualKyc NonIndividualKyc].include?(base)
    base = "Approval" if base == "ApprovalResponse"

    candidates = [
      "#{base}Mailer",
      "#{base}sMailer",
      "#{base}NotificationMailer",
      "#{base}NotificationsMailer"
    ]

    candidates.each do |class_name|
      klass = class_name.safe_constantize
      return klass if klass
    end

    raise NameError, "Mailer class not found for #{base}"
  end

  def preview
    # Get the resource name from the controller (e.g., "users" -> "user")
    resource_name = controller_name.singularize
    resource_name = "investor_kyc" if %w[individual_kyc non_individual_kyc].include?(resource_name)

    # Build the instance variable name (e.g., "@user")
    instance_var = "@#{resource_name}"
    # Fetch the resource instance variable
    resource = instance_variable_get(instance_var)

    # Raise an error if the resource is not found
    raise "#{instance_var} is nil" if resource.nil?

    # Determine the mailer class for the resource (e.g., UserMailer)
    mailer_class = resolve_mailer_class(resource)
    # Default to "notify_<resource_name>" if no email_method is provided
    email_method = params[:email_method].presence || "notify_#{resource_name}"

    # Try to get the associated investor and their approved access
    investor = resource.try(:investor)
    @investor_access = investor&.investor_accesses&.approved&.first

    if @investor_access.present?
      # Build the mail object with required parameters
      mail = mailer_class
             .with(
               "#{resource_name}_id": resource.id,
               email_method:,
               user_id: @investor_access.user_id,
               entity_id: resource.try(:entity_id)
             )
             .public_send(email_method)

      # Get the HTML part of the email (or the mail itself if no multipart)
      html_part = mail.html_part || mail
      @html_body = html_part.body.decoded
      @attachments = mail.attachments

      # Render the email preview without layout
      render "/layouts/email_preview", layout: false
    else
      # If no approved access, show an error message with layout
      @error_message = "No approved investor access found for this user"
      Rails.logger.debug @error_message
      render "/layouts/email_preview", layout: true
    end
  rescue StandardError => e
    # Handle any exceptions, show fallback or default error message
    @error_message = "Unable to preview email"
    Rails.logger.debug e.message
    Rails.logger.debug e.backtrace.join("\n")
    @exception_message = e.message
    render "/layouts/email_preview", layout: true
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
    # If snapshot is present, we need to return records with_snapshots
    model_class = model_class.with_snapshots if params[:snapshot].present?
    # Get the ransack search object
    @q = model_class.ransack(params[:q])
    # Create the scope for the model
    policy_scope(@q.result)
  end

  def filter_params(scope, *keys)
    keys.each do |key|
      scope = scope.where(key => params[key]) if params[key].present?
    end
    scope
  end

  def filter_range(scope, column, start_date:, end_date:)
    return scope unless start_date.present? || end_date.present?

    if start_date.present? && end_date.present?
      scope.where(column => start_date..end_date)
    elsif start_date.present?
      scope.where("#{column} >= ?", start_date)
    else # end_date.present?
      scope.where("#{column} <= ?", end_date)
    end
  end

  def set_locale
    # Priority: params[:locale] > session[:locale] > browser
    I18n.locale = params[:locale]&.to_sym || session[:locale]&.to_sym || extract_locale_from_accept_language_header || I18n.default_locale
    Rails.logger.debug { "Locale set to: #{I18n.locale}" }
    session[:locale] = I18n.locale
  end

  def extract_locale_from_accept_language_header
    # Looks at browser settings: Accept-Language
    http_accept_language = request.env['HTTP_ACCEPT_LANGUAGE']
    return nil if http_accept_language.blank?

    # Find the first available locale that matches
    parsed_locales = http_accept_language.scan(/[a-z]{2}/)
    parsed_locales.find { |locale| I18n.available_locales.include?(locale.to_sym) }
  end
end
