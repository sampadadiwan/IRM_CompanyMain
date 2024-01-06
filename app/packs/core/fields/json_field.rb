require "administrate/field/base"

class JsonField < Administrate::Field::Base
  TABLE_OPTIONS = { table_class: "table table-bordered dataTable" }.freeze
  delegate :to_s, to: :data

  def json2table
    updated_data = if data.is_a?(Hash)
                     data.to_json
                   else
                     # handle other cases
                     data
                   end
    Json2table.get_html_table(updated_data, TABLE_OPTIONS).html_safe
  end
end
