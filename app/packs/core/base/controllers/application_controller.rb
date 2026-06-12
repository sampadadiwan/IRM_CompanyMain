class ApplicationController < ActionController::Base
  layout 'modernize'
  include Pagy::Backend
  include Pundit::Authorization

  include WithAuthentication
  include WithFilterParams
  include WithBulkActions
  include WithEmailPreview
  include WithLocale
  include WithSetupCustomFields
  include UserGuideHelper

  before_action :prepare_exception_notifier
  before_action :validate_page_limit

  def validate_page_limit
    return unless params.key?(:per_page)

    per_page = params[:per_page].to_i

    if per_page <= 0
      params[:per_page] = 10
    elsif per_page > 1000
      params[:per_page] = 1000
    end
  end

  # Override current_user to support signed_id access in policies
  def current_user
    return @signed_id_user if @signed_id_user

    super
  end

  def restore_deleted
    model_class = controller_name.classify.constantize
    record = model_class.only_deleted.find(params[:id])
    authorize record, :destroy?

    # Check for associated folders that might also be deleted
    %w[document_folder_id data_room_folder_id].each do |folder_attr|
      if record.respond_to?(folder_attr) && record.send(folder_attr).present?
        folder = Folder.only_deleted.find_by(id: record.send(folder_attr))
        folder&.restore(recursive: true)
      end
    end

    record.restore(recursive: true)
    redirect_to record, notice: "#{model_class.model_name.human} was successfully restored."
  end

  def show_deleted
    authorize controller_name.classify.constantize, :index?
    model_class = controller_name.classify.constantize
    @q = model_class.only_deleted.ransack(params[:q])
    @pagy, @records = pagy(policy_scope(@q.result))

    render "layouts/deleted_index"
  end

  private

  def rss_kb
    # RSS in KB for current process
    `ps -o rss= -p #{Process.pid}`.to_i
  end

  def log_memory_delta
    before = rss_kb
    yield
  ensure
    after = rss_kb
    delta_mb = (after - before) / 1024.0
    Rails.logger.info("[mem] #{request.request_method} #{request.fullpath} pid=#{Process.pid} ΔRSS=#{delta_mb.round(1)}MB (#{before / 1024}→#{after / 1024}MB)")
  end

  # Finds a record and user from a signed ID and sets up the session for guest access.
  # This is used for public/shared links where a user might not be logged in.
  #
  # @param signed_id [String] The signed ID containing record and user information.
  # @return [void] Sets instance variables @[model_name] and @signed_id_user if successful.
  #
  # @example
  #   find_by_signed_id_for_user(params[:signed_id])
  #   # Sets @kpi_report and @signed_id_user if the signed ID is for a KpiReport.

  # Resolves the ordered list of named dashboards and the active dashboard name for a given
  # dashboard_type. User preferences can override alphabetical order and the default selection.
  #
  # Returns [dashboard_names, name] where:
  #   dashboard_names - ordered array of distinct dashboard names for the dropdown
  #   name            - the active dashboard name (from params, then preference, then "Default")
  def resolve_dashboard(dashboard_type, requested_name)
    raw_names = DashboardWidget.enabled
                               .where(dashboard_name: dashboard_type, entity_id: current_user.entity_id)
                               .distinct.pluck(:name)

    sequence = current_user.dashboard_sequence(dashboard_type)
    ordered = if sequence.any?
                (sequence & raw_names) + (raw_names - sequence).sort
              else
                raw_names.sort
              end

    name = requested_name || sequence.first || "Default"
    [ordered, name]
  end

  # rubocop:disable Rails/DynamicFindBy
  def find_by_signed_id_for_user(signed_id)
    return if signed_id.blank?

    record, user = ApplicationRecord.find_by_signed_id_for_user(signed_id)
    return unless record && user

    # Mark the user as having signed ID access for policy authorization.
    # This allows Pundit policies to check if access was granted via a shared link.
    user.define_singleton_method(:signed_id_access?) { true }

    # Dynamically set the instance variable based on the record's base class name.
    # Using base_class handles STI subclasses (e.g., IndividualKyc → @investor_kyc).
    instance_variable_set("@#{record.class.base_class.name.underscore}", record)
    @signed_id_user = user
  end
  # rubocop:enable Rails/DynamicFindBy
end
