module JsonTable
  extend ActiveSupport::Concern

  TABLE_OPTIONS = {
    table_style: "border: 1px solid black; max-width: 600px;",
    table_class:
    "table table-striped table-hover table-condensed table-bordered",
    table_attributes: "border=1"
  }.freeze

  def json_table
    return "" if response.blank?

    Json2table.get_html_table(response, TABLE_OPTIONS)
  end
end
