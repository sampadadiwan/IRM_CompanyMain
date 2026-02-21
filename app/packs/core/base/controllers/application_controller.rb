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

  before_action :prepare_exception_notifier

  # Override current_user to support signed_id access in policies
  def current_user
    return @signed_id_user if @signed_id_user

    super
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

  # rubocop:disable Rails/DynamicFindBy
  def find_by_signed_id_for_user(signed_id)
    return if signed_id.blank?

    record, user = ApplicationRecord.find_by_signed_id_for_user(signed_id)
    return unless record && user

    # Mark the user as having signed ID access for policy authorization.
    # This allows Pundit policies to check if access was granted via a shared link.
    user.define_singleton_method(:signed_id_access?) { true }

    # Dynamically set the instance variable based on the record's class name.
    # For example, if record is a KpiReport, it sets @kpi_report.
    instance_variable_set("@#{record.class.name.underscore}", record)
    @signed_id_user = user
  end
  # rubocop:enable Rails/DynamicFindBy
end
