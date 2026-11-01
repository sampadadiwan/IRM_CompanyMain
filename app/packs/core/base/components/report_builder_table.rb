# The report page's table: values formatted by column type (the same rules as
# the preview and the Excel export), sortable column headers, and the totals row.
#
# Worked examples H15, H17, H20, E18, E19, E23 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderTable < ViewComponent::Base
  # sort: the sort in effect ({ key:, dir: }); totals: a ReportBuilderTotals;
  # sort_capped: true when a computed sort stopped at the engine's row cap
  def initialize(report:, columns:, rows:, q:, formatter:, totals: nil, sort: {}, sort_capped: false,
                 turbo_frame: "report_builder_view")
    super()
    @report      = report
    @columns     = columns
    @rows        = rows
    @q           = q
    @formatter   = formatter
    @totals      = totals
    @sort        = sort || {}
    @sort_capped = sort_capped
    @turbo_frame = turbo_frame
  end

  private

  attr_reader :columns, :rows, :formatter

  def column_label(col)
    col.respond_to?(:label) ? col.label.presence || col.name : col[:label]
  end

  def clean_key(col)
    col.key.to_s.split(";").first.strip
  end

  def value_for(row, col)
    row[col.key].nil? ? row[clean_key(col)] : row[col.key]
  end

  # Header link: first click sorts lowest first, the next highest first.
  # Keeps the search and other params; starts again at page 1.
  def sort_link_params(col)
    key = clean_key(col)
    dir = sorted_by?(col) && @sort[:dir] == "asc" ? "desc" : "asc"
    helpers.request.query_parameters.except("page").merge("sort" => key, "dir" => dir)
  end

  def sorted_by?(col)
    @sort[:key].present? && @sort[:key] == clean_key(col)
  end

  def sort_icon(col)
    return "ti-arrows-sort text-muted" unless sorted_by?(col)

    @sort[:dir] == "desc" ? "ti-sort-descending" : "ti-sort-ascending"
  end

  def totals
    @totals&.call
  end

  def totals_label
    @totals&.label
  end

  def computed_sort_cap
    ReportBuilderQueryEngine::MAX_COMPUTED_SORT_ROWS
  end
end
