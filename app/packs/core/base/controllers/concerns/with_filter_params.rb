# Provides filtering, searching, and export utilities for controllers.
#
# This concern adds helper methods to:
# - Perform Ransack-based searches with optional snapshot filtering and policy scoping.
# - Filter ActiveRecord relations by specific parameters or date ranges.
# - Render records as XLSX files, supporting custom report templates.
#
# == Instance Methods
#
# ransack_with_snapshot::
#   Performs a Ransack search on the controller's model, applies policy scope, and optionally filters for records with snapshots.
#
# filter_params(scope, *keys)::
#   Filters the given scope by matching params for the specified keys, if present.
#
# filter_range(scope, column, start_date:, end_date:)::
#   Filters the scope by a date range on the given column, supporting open-ended ranges.
#
# render_xlsx(records, template: "index")::
#   Renders records as an XLSX file, using a custom report template if specified, or falls back to a standard template.
#
# @see https://github.com/activerecord-hackery/ransack Ransack gem documentation
# @see https://github.com/varvet/pundit Pundit gem documentation for policy_scope
module WithFilterParams
  extend ActiveSupport::Concern

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

  # Renders the given records as an XLSX (Excel) file using the specified template.
  #
  # @param records [ActiveRecord::Relation, Array] The collection of records to be exported to XLSX.
  # @param template [String] The name of the template to use for rendering the XLSX file (default: "index").
  # @return [void] This method sends the XLSX file as a response and does not return a value.
  #
  # @example
  #   render_xlsx(@users, template: "users/index")
  #
  # Note: Ensure the corresponding XLSX template exists and is properly configured.
  def render_xlsx(records, template: "index")
    if params[:custom_xls_report].present? && params[:report_id].present?
      @report = Report.find(params[:report_id])
      if @report.template_xls.present?
        xlsx = XlsxFromTemplate.generate_and_stream(@report.template, records, @report.metadata)
        send_data xlsx, filename: "#{@report.name}.xlsx", type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      else
        render json: { error: "Template XLS not found for report #{@report.id}" }, status: :not_found
      end
    else
      render template
    end
  end
end
