module WithReportBuilderViews
  extend ActiveSupport::Concern

  included do
    before_action :set_report_builder_view, only: :index
  end

  private

  def set_report_builder_view
    return unless params[:view_id].present?

    @report_view = Report.find_by(id: params[:view_id], is_view: true)
    return unless @report_view

    # Verify entity scoping
    return unless @report_view.entity_id == current_user.entity_id

    # Run the query engine
    engine = ReportBuilderQueryEngine.new(
      report: @report_view,
      entity: current_user.entity,
      external_filters: params[:q]
    )
    
    @rows = engine.run
    @columns = engine.columns
    @is_custom_view = true

    # Paginate custom rows
    @pagy, @rows = pagy_array(@rows, limit: params[:per_page])
  end
end
