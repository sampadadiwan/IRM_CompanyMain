class CreateDefaultCustomGridView
  def initialize(form_type_id)
    @form_type = FormType.find(form_type_id)
  end

  attr_accessor :form_type

  def find_or_create
    column_pair = form_type.name.constantize::STANDARD_COLUMNS
    column_pair = column_pair.dup
    custom_fields = form_type.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s)
    custom_fields.each do |column|
      display_name = column.split('_').map(&:capitalize).join(' ')
      column_pair[display_name] = "custom_fields.#{column}"
    end
    column_hash = transform_columns(column_pair)

    custom_grid_view = CustomGridView.find_or_create_by!(owner_id: form_type.id, owner_type: "FormType")

    column_hash.each do |display_name, attributes|
      grid_view_preference = custom_grid_view.grid_view_preferences.find_or_initialize_by(key: attributes[:key])
      grid_view_preference.update!(name: display_name, key: attributes[:key], sequence: attributes[:sequence] + 1, selected: attributes[:selected])
    end
    custom_grid_view
  end

  def update
    custom_grid_view = CustomGridView.find_by(owner_id: form_type.id, owner_type: "FormType")
    return unless custom_grid_view

    existing_preferences = custom_grid_view.grid_view_preference
    new_column_pair = form_type.name.constantize::STANDARD_COLUMNS.dup

    custom_fields = form_type.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s)
    custom_fields.each do |column|
      display_name = column.split('_').map(&:capitalize).join(' ')
      new_column_pair[display_name] = "custom_fields.#{column}"

      display_name = column.split('_').map(&:capitalize).join(' ')
      next if existing_preferences.key?(display_name)

      existing_preferences[display_name] = {
        key: "custom_fields.#{column}",
        sequence: existing_preferences.size,
        selected: false
      }
    end

    existing_preferences.each_key do |key|
      existing_preferences.delete(key) unless new_column_pair.key?(key) || form_type.name.constantize::STANDARD_COLUMNS.key?(key)
    end

    existing_preferences.each_with_index do |(_key, value), index|
      value[:sequence] = index
    end

    custom_grid_view.update!(grid_view_preference: existing_preferences)
  end

  private

  def transform_columns(columns)
    column_hash = {}
    columns.each_with_index do |column, index|
      show_in_grid = form_type.name.constantize::STANDARD_COLUMNS.key?(column[0])
      column_hash[column[0]] = { key: column[1], sequence: index, selected: show_in_grid }
    end
    column_hash
  end
end
