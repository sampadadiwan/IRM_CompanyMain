module JsonTable
  extend ActiveSupport::Concern

  TABLE_OPTIONS = {
    table_style: "margin: 5px;",
    table_class: "table table-bordered no_hover_table",
    table_attributes: ""
  }.freeze

  def json_table
    return "" if response.blank?

    Json2table.get_html_table(response, TABLE_OPTIONS)
  end
end
