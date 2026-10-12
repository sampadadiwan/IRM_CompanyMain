class RansackTable < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include Pagy::Frontend
  include ApplicationHelper

  # sortable: false renders plain header labels instead of Ransack sort links.
  # Use it for tables that rely on client-side (jQuery DataTables) sorting only,
  # to avoid showing two sets of sort arrows per column.
  # required_columns / excluded_columns: see RansackTableHeader.
  def initialize(model, q:, turbo_frame:, pagy:, default_columns_map: nil, entity: nil, current_user: nil, records: nil, report_id: nil, id: "", header_css_class: "", table_css_class: "", referrer: nil, snapshot: nil, actions_column: true, sortable: true, required_columns: nil, excluded_columns: nil)
    super()
    @records = records
    @model = model
    @partial_base_path = @model.model_name.plural
    @partial_name = @model.model_name.element
    @turbo_frame = turbo_frame
    @pagy = pagy
    @actions_column = actions_column
    @table_css_class = table_css_class

    @ransack_table_header = RansackTableHeader.new(model, q: q, turbo_frame: turbo_frame, default_columns_map: default_columns_map, entity: entity, current_user: current_user, records: records, report_id: report_id, id: id, css_class: header_css_class, referrer: referrer, snapshot: snapshot, actions_column: actions_column, sortable: sortable, required_columns: required_columns, excluded_columns: excluded_columns)
  end
  # rubocop:enable Naming/MethodParameterName
end
