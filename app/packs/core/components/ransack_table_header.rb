class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include ApplicationHelper

  def initialize(model, q:, columns_map: nil, entity: nil, current_user: nil, records: nil, report_id: nil, id: "", css_class: "")
    super
    @model = model
    @q = q.presence || @model.ransack
    @id = id
    @current_user = current_user
    @entity = entity.presence || get_owner_entity(records)
    @css_class = css_class
    @report_id = report_id
    @columns_map = columns_map.presence || get_columns(@entity)
  end

  attr_accessor :columns, :entity, :current_user

  def get_columns(entity)
    report = Report.find_by(id: @report_id)
    columns = fetch_report_columns(report) if report.present?
    columns = fetch_custom_columns(entity) if columns.blank?
    columns = @model::STANDARD_COLUMNS if columns.blank?
    columns
  end

  private

  def fetch_report_columns(report)
    report.selected_columns.presence || @model::STANDARD_COLUMNS
  end

  def fetch_custom_columns(entity)
    return @model::STANDARD_COLUMNS if entity.nil?

    form_type = entity.form_types.includes(:grid_view_preferences)
                      .find_by(name: @model.to_s)
    form_type&.selected_columns
  end

  def get_owner_entity(records)
    owner_entity(records, current_user)
  end
end
