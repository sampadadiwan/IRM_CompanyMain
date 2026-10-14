class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include ApplicationHelper

  # sortable: false renders plain header labels (no Ransack sort links/arrows),
  # for tables where sorting is handled client-side by jQuery DataTables.
  # required_columns / excluded_columns adjust whatever column set is resolved (report,
  # entity's saved columns or default) for the page it is shown on: required_columns
  # ({"Label; css" => "key; css"}) are put at the front when their key is missing,
  # excluded_columns (plain keys, e.g. "investor_name") are dropped.
  def initialize(model, q:, turbo_frame:, default_columns_map: nil, entity: nil, current_user: nil, records: nil, report_id: nil, id: "", css_class: "", referrer: nil, snapshot: nil, actions_column: true, sortable: true, required_columns: nil, excluded_columns: nil)
    super()
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
    @default_columns_map = default_columns_map
    @sortable = sortable
    @required_columns = required_columns.presence || {}
    @excluded_columns = Array(excluded_columns)
    # fetch columns uses @referrer in the cache key, it should have a value assigned before use
    @columns = fetch_columns(@entity, default_columns_map)
    @actions_column = actions_column
    # Column help: a model can define COLUMN_HELP { "attribute" => "what it means" }; those column
    # headers get an info icon with that text (LP and fund team grids alike)
    @column_help = @model.const_defined?(:COLUMN_HELP) ? @model::COLUMN_HELP : {}
    if @snapshot
      # We need to add the snapshot_date to the columns in 2nd last position
      @columns["Snapshot Date"] = "snapshot_date"
    end
  end

  attr_accessor :columns, :entity, :current_user, :actions_column

  def ag_selected_columns
    report = Report.find_by(id: @report_id)
    columns = report.ag_selected_columns if report.present?

    form_type = entity.form_types.find_by(name: @model.to_s)
    columns = form_type&.ag_selected_columns if columns.blank?

    if columns.blank? && @default_columns_map.present?
      # If default_columns_map is a Hash (STANDARD_COLUMNS format), convert it to AG Grid format
      columns = if @default_columns_map.is_a?(Hash)
                  @default_columns_map.map do |label, key|
                    clean_label = label.split(";").first.strip
                    clean_key = key.split(";").first.strip
                    # Try to infer data type
                    data_type = if clean_key.include?("custom_fields.")
                                  ApplicationRecord::DEFAULT_DATA_TYPE
                                else
                                  @model.columns_hash[clean_key]&.type.to_s.capitalize.presence ||
                                    @model.columns_hash["#{clean_key}_cents"]&.type.to_s.capitalize.presence ||
                                    ApplicationRecord::DEFAULT_DATA_TYPE
                                end
                    { label: clean_label, key: clean_key, data_type: data_type }
                  end
                else
                  @default_columns_map
                end
    end

    columns = @model.ag_grids_default_columns if columns.blank?
    columns = adjust_ag_columns(columns)
    # Makes ag grid col link works correctly
    # enforce data types from default columns
    # this is to ensure that even if the user has saved the column as a string,
    # if the code says it should be html, we render it as html
    if @model.respond_to?(:ag_grids_default_columns)
      default_columns = @model.ag_grids_default_columns
      default_columns_map = default_columns.index_by { |col| col[:key] }
      columns = columns.map do |col|
        col = col.with_indifferent_access
        col_key = col[:key]
        if default_columns_map[col_key]
          default_type = default_columns_map[col_key][:data_type]
          # If the default type involves special rendering (not String), prefer it
          col[:data_type] = default_type if default_type != "String"
        end
        col
      end
    end

    columns
  end

  private

  def cache_key(default_columns_map)
    # default_columns_map must be part of the key: callers like fund_formulas pick a
    # different map per-request (e.g. params[:debug]), and without this the cached
    # result from one variant gets served to the other until the 5-day expiry.
    # required/excluded columns too: the same entity's columns are adjusted differently per page.
    ["#{@model}Header", current_user, entity, @referrer, @report_id, default_columns_map, @required_columns, @excluded_columns]
  end

  def fetch_columns(entity, default_columns_map)
    Rails.cache.fetch(cache_key(default_columns_map), expires_in: 5.days) do
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
    adjust_columns(columns)
  end

  # The plain attribute key of a "key; css-class" column value
  def bare_key(value)
    value.to_s.split(";").first.strip
  end

  # Applies required/excluded columns to a {"Label; css" => "key; css"} column map
  def adjust_columns(columns)
    return columns if @required_columns.empty? && @excluded_columns.empty?

    # Drop the columns this page has no use for
    kept = columns.reject { |_label, key| @excluded_columns.include?(bare_key(key)) }
    # Prepend the required columns the resolved set does not already have, in the given order
    present_keys = kept.values.map { |key| bare_key(key) }
    missing = @required_columns.reject { |_label, key| present_keys.include?(bare_key(key)) }
    missing.merge(kept)
  end

  # Same adjustment for AG Grid's [{label:, key:, data_type:}] column list
  def adjust_ag_columns(columns)
    return columns if @required_columns.empty? && @excluded_columns.empty?

    # Drop the excluded keys
    kept = columns.reject { |col| @excluded_columns.include?(col.with_indifferent_access[:key].to_s) }
    present_keys = kept.map { |col| col.with_indifferent_access[:key].to_s }
    # Build AG Grid entries for the missing required columns, typed from the model's AG defaults
    ag_defaults = @model.respond_to?(:ag_grids_default_columns) ? @model.ag_grids_default_columns.index_by { |col| col[:key] } : {}
    missing = @required_columns.filter_map do |label, key|
      clean_key = bare_key(key)
      next if present_keys.include?(clean_key)

      { label: bare_key(label), key: clean_key, data_type: ag_defaults.dig(clean_key, :data_type) || ApplicationRecord::DEFAULT_DATA_TYPE }
    end
    missing + kept
  end

  def get_owner_entity(records)
    owner_entity(records, current_user)
  end
end
