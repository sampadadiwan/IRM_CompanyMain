class ApplicationController < ActionController::Base
  layout 'modernize'

  include Pundit::Authorization
  include PublicActivity::StoreController

  skip_before_action :verify_authenticity_token if ENV['SKIP_AUTHENTICITY_TOKEN'] == "true"

  after_action :verify_authorized, except: %i[index search], unless: :devise_controller?
  after_action :verify_policy_scoped, only: [:index]

  before_action :set_current_entity
  before_action :authenticate_user!
  before_action :set_search_controller
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_paper_trail_whodunnit

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name phone role entity_id whatsapp_enabled dept call_code])
  end

  SEARCH_CONTROLLERS = %w[notes access_rights entities holdings excercises
                          holding_audit_trails offers documents tasks investment_opportunities].freeze

  def set_search_controller
    @search_controller = SEARCH_CONTROLLERS.include?(params[:controller]) ? params[:controller] : nil
  end

  rescue_from Pundit::NotAuthorizedError do |_exception|
    redirect_to root_path, alert: "Access Denied"
  end

  rescue_from ActionController::InvalidAuthenticityToken do |_exception|
    redirect_path = request.referer || root_path
    redirect_to redirect_path, alert: "Please refresh screen and retry"
  end

  before_action :prepare_exception_notifier

  private

  def prepare_exception_notifier
    request.env["exception_notifier.exception_data"] = {
      current_user:
    }
  end

  def after_sign_out_path_for(_resource_or_scope)
    request.referer
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || root_path
  end

  def setup_custom_fields(model, type: nil)
    # Custom form fields
    form_type = if type.present?
                  FormType.where(entity_id: model.entity_id, name: type).first
                else
                  FormType.where(entity_id: model.entity_id, name: model.class.name).first
                end
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
    if request.subdomain.present? && !ENV['HOST'].starts_with?(request.subdomain)
      @current_entity = Entity.where(sub_domain: request.subdomain).load_async.first
      redirect_to(ENV.fetch('BASE_URL', nil), allow_other_host: true) unless @current_entity
    end
  end
end
