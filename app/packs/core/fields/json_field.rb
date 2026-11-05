require "administrate/field/base"

class JsonField < Administrate::Field::Base
  TABLE_OPTIONS = { table_class: "table table-bordered dataTable" }.freeze
  delegate :to_s, to: :data

  def json2table
    if data.present?
      updated_data = if data.is_a?(Hash)
                       data.to_json
                     else
                       # handle other cases
                       data
                     end
      # Admin screens show JSON from every firm to support staff; Json2table does not escape values,
      # so sanitize its output (SafeHtml.json_table) rather than marking it html_safe.
      SafeHtml.json_table(updated_data, TABLE_OPTIONS)
    else
      ""
    end
  end
end
