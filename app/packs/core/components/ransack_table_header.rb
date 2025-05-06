class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include ApplicationHelper

  def initialize(model, q:, turbo_frame:, default_columns_map: nil, entity: nil, current_user: nil, records: nil, report_id: nil, id: "", css_class: "", referrer: nil, snapshot: nil)
    super
    @model = model
    @q = q.presence || @model.ransack
    @id = id
    @current_user = current_user
    @entity = entity.presence || get_owner_entity(records)
    @css_class = css_class
    @turbo_frame = turbo_frame
    @report_id = report_id
    @referrer = referrer
    @snapshot = snapshot
    # fetch columns uses @referrer in the cache key, it should have a value assigned before use
    @columns = fetch_columns(@entity, default_columns_map)

    if @snapshot
      # We need to add the snapshot_date to the columns in 2nd last position
      @columns["Snapshot Date"] = "snapshot_date"
    end
  end

  attr_accessor :columns, :entity, :current_user

  def ag_selected_columns
    report = Report.find_by(id: @report_id)
    columns ||= report.ag_selected_columns if report.present?

    form_type = entity.form_types.find_by(name: @model.to_s)
    columns ||= form_type.ag_selected_columns
    columns ||= default_columns_map
    columns ||= @model.ag_grids_default_columns

    columns
  end

  private

  def cache_key
    ["#{@model}Header", current_user, entity, @referrer, @report_id]
  end

  def fetch_columns(entity, default_columns_map)
    Rails.cache.fetch(cache_key, expires_in: 5.days) do
      get_columns(entity, default_columns_map)
    end
  end

  # Fetches the columns based on the report or entity
  def get_columns(entity, default_columns_map)
    report = Report.find_by(id: @report_id)
    columns = report.selected_columns if report.present?

    form_type = entity.form_types.find_by(name: @model.to_s)
    columns = form_type&.selected_columns if columns.blank?
    columns = default_columns_map if columns.blank?
    columns = @model::STANDARD_COLUMNS if columns.blank?
    columns
  end

  def get_owner_entity(records)
    owner_entity(records, current_user)
  end
end
