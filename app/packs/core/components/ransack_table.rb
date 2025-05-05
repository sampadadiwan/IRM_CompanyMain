class RansackTable < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include ApplicationHelper

  # rubocop:disable Metrics/ParameterLists
  # rubocop:disable Naming/MethodParameterName
  def initialize(model, q:, turbo_frame:, default_columns_map: nil, entity: nil, current_user: nil, records: nil, report_id: nil, id: "", css_class: "", referrer: nil, snapshot: nil)
    super
    @records = records
    @model = model
    @partial_base_path = @model.model_name.plural
    @partial_name = @model.model_name.element
    @turbo_frame = turbo_frame

    @ransack_table_header = RansackTableHeader.new(model, q: q, turbo_frame: turbo_frame, default_columns_map: default_columns_map, entity: entity, current_user: current_user, records: records, report_id: report_id, id: id, css_class: css_class, referrer: referrer, snapshot: snapshot)
  end
  # rubocop:enable Naming/MethodParameterName
  # rubocop:enable Metrics/ParameterLists
end
