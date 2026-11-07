# What the columns side panel shows: its title and note, the listed columns and the columns that can be added.
# openspec/changes/grid-columns-inline-settings — design card ③; worked examples H1, H3, H5, E2, E3, E4, E11
module GridColumnsHelper
  # "Investors", "Capital Commitments"
  def grid_columns_plural(context)
    context.model_class.model_name.human.pluralize.titleize
  end

  # The panel title and the toast's subject: "Investors columns", or H5 "'LPs by city' columns"
  def grid_columns_title(context)
    context.report ? "'#{context.report.name}' columns" : "#{grid_columns_plural(context)} columns"
  end

  # The one-line "who shares this" note under the title, and its fuller tooltip
  def grid_columns_note(context)
    if context.report
      ["Shared with everyone who opens this report",
       "These columns belong to the saved report '#{context.report.name}': everyone who opens it sees the change. " \
       "The firm's #{grid_columns_plural(context)} columns are not changed."]
    else
      ["Shared with everyone in your firm, on every #{grid_columns_plural(context)} table",
       "Columns belong to your firm, not to one person: every #{grid_columns_plural(context)} table in the firm " \
       "(not only this page) shows the change, for everyone."]
    end
  end

  # The rows the panel lists when it opens:
  #   - the owner's saved columns (H1), flagged "not shown on this page" when the page hides them (E3);
  #   - else the columns the table showed (H3 — the page's standard columns; E4 — a report without its own);
  #   - plus, locked at the top, the columns this page always adds that the list lacks (E2).
  # E11 — the snapshot column was never put in the context.
  # @return [Array<Hash>] { id:, key:, label:, type:, derived:, locked:, hidden: }
  def grid_columns_rows(context)
    owner = context.owner
    saved = owner.persisted? ? owner.grid_view_preferences.order(:sequence).to_a : []
    rows = if saved.any?
             saved.map { |preference| grid_columns_saved_row(context, preference) }
           else
             context.shown.map { |label, key| grid_columns_new_row(context, key, label) }
           end
    with_locked_rows(context, rows)
  end

  # X4, X6 — the panel again after a refused save, from the list as submitted (unknown ids and unreadable rows
  # are left out; the reasons are shown above the list)
  def grid_columns_rows_from_submission(context, json)
    submitted = begin
      JSON.parse(json.to_s)
    rescue JSON::ParserError
      []
    end
    submitted = [] unless submitted.is_a?(Array)
    saved = context.owner.persisted? ? context.owner.grid_view_preferences.index_by(&:id) : {}

    rows = submitted.filter_map do |row|
      next unless row.is_a?(Hash)

      if row["id"].present?
        preference = saved[row["id"].to_i]
        preference && grid_columns_saved_row(context, preference).merge(label: row["label"].to_s)
      elsif ActiveModel::Type::Boolean.new.cast(row["derived"])
        # H18 — a derived field typed in the panel
        { id: nil, key: row["key"].to_s, label: row["label"].to_s, type: row["data_type"].presence || GridViewPreference::DEFAULT_DATA_TYPE,
          derived: true, alignment: row["alignment"].presence, locked: false, hidden: false }
      elsif row["key"].present?
        grid_columns_new_row(context, row["key"], row["label"].to_s)
      end
    end
    with_locked_rows(context, rows)
  end

  # The "Add a column" groups: [[group, [[label, key, type], ...]], ...]. Related labels lose their "Investor."
  # prefix (the group says it) and any "; css" part.
  def grid_columns_add_options(context)
    GridColumnOptions.new(context.model_class, context.entity.id).call.map do |group, options|
      [group, options.map { |label, key| [label.split(";").first.strip.delete_prefix("#{group}."), key, grid_column_type(context.model_class, key)] }]
    end
  end

  # The data type chip of a column, worked out as GridViewPreference#custom_data_type does
  def grid_column_type(model_class, key)
    clean = GridColumnOptions.clean(key)
    return GridViewPreference::DEFAULT_DATA_TYPE if clean.include?("custom_fields.") || clean.include?(".")

    column = model_class.columns_hash[clean] || model_class.columns_hash["#{clean}_cents"]
    column&.type.to_s.capitalize.presence || GridViewPreference::DEFAULT_DATA_TYPE
  end

  private

  def grid_columns_saved_row(context, preference)
    clean_key = preference.clean_key
    { id: preference.id, key: clean_key, label: preference.clean_label,
      type: preference.data_type.presence || grid_column_type(context.model_class, clean_key),
      derived: preference.derived_field ? true : false, locked: false, alignment: preference.alignment,
      hidden: context.excluded.include?(clean_key) }
  end

  def grid_columns_new_row(context, key, label)
    clean_key = GridColumnOptions.clean(key)
    { id: nil, key: key.to_s, label: label.to_s.split(";").first.to_s.strip,
      type: grid_column_type(context.model_class, clean_key), derived: false, alignment: nil,
      locked: context.required.include?(clean_key), hidden: context.excluded.include?(clean_key) }
  end

  # E2 — the page's always-shown columns the list lacks go first, locked (never submitted, never saved)
  def with_locked_rows(context, rows)
    present = rows.map { |row| GridColumnOptions.clean(row[:key]) }
    missing = context.required.reject { |key| present.include?(key) }.map do |key|
      label = context.shown.find { |_l, k| GridColumnOptions.clean(k) == key }&.first || key.humanize
      grid_columns_new_row(context, key, label).merge(locked: true)
    end
    missing + rows
  end
end
