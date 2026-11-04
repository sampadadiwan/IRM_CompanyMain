# Writes a Report Builder report to Excel: one "Data" sheet with the report
# name, a filter summary, headers, the rows and — as its last row — the bold
# totals row. Values go through ReportBuilderValueFormatter, so amounts and
# dates are real number and date cells (sorting and SUM work in Excel) and
# look the same as on screen; totals come from ReportBuilderTotals.
#
# Worked examples H16, H19 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderXlsxExporter
  HEADER_COLOR  = "2D5BA3".freeze
  ALT_ROW_COLOR = "F0F4F8".freeze

  def initialize(report:, rows:, columns: nil)
    @report    = report
    @rows      = rows
    @config    = ReportBuilderConfig.new(report.template)
    @columns   = columns || report.grid_view_preferences.reorder(:sequence, :id).to_a
    @formatter = ReportBuilderValueFormatter.new(config: @config, entity: report.entity)
    @styles    = {}
  end

  # Returns raw xlsx binary string.
  def generate
    package = Axlsx::Package.new
    add_data_sheet(package.workbook)
    package.to_stream.read
  end

  private

  attr_reader :report, :rows, :config, :columns, :formatter

  # ── Sheet ────────────────────────────────────────────────────────────────

  def add_data_sheet(wb)
    wb.add_worksheet(name: "Data") do |sheet|
      col_count = columns.length

      # Row 1: report name
      sheet.add_row [report.name], style: [style(wb, b: true, sz: 13)]
      sheet.merge_cells("A1:#{col_letter(col_count)}1") if col_count > 1

      # Row 2: filter summary
      sheet.add_row [filter_summary], style: [style(wb, sz: 9, fg_color: "888888")]
      sheet.merge_cells("A2:#{col_letter(col_count)}2") if col_count > 1

      # Row 3: headers
      sheet.add_row(column_headers, style: columns.map { |c| header_style(wb, c) })
      sheet.sheet_view.pane do |p|
        p.top_left_cell = "A4"
        p.state         = :frozen
        p.y_split       = 3
      end
      sheet.auto_filter = "A3:#{col_letter(col_count)}3"

      add_data_rows(wb, sheet, col_count)
      add_totals_row(wb, sheet)

      # Auto-fit column widths from the header and up to 200 displayed values
      columns.each_with_index do |col, i|
        sample = [column_headers[i].to_s] + rows.first(200).map { |r| formatter.display(r[col.key], col) }
        sheet.column_info[i].width = [sample.map(&:length).max.to_i + 2, 8].max
      end
    end
  end

  def add_data_rows(wb, sheet, col_count)
    group_col     = config.group_rows_by
    current_group = nil

    # Sort rows by group if grouping is enabled
    sorted_rows = group_col.present? ? rows.sort_by { |r| r[group_col].to_s } : rows

    sorted_rows.each_with_index do |row_data, idx|
      if group_col.present?
        group_val = row_data[group_col].to_s
        if group_val != current_group
          # A group header row starts each collapsible group
          sheet.add_row [group_val], style: style(wb, b: true, sz: 13)
          sheet.merge_cells("A#{sheet.rows.size}:#{col_letter(col_count)}#{sheet.rows.size}")
          current_group = group_val
        end
      end

      # [value, number format] per cell — numbers and dates stay typed (H16)
      cells  = columns.map { |c| formatter.xlsx(row_data[c.key], c) }
      styles = columns.each_with_index.map { |c, i| cell_style(wb, c, cells[i][1], alt: idx.odd?) }

      row_opts = {}
      row_opts[:outline_level] = 1 if group_col.present?
      sheet.add_row(cells.map(&:first), style: styles, **row_opts)
    end
  end

  # The bold totals row, last on the sheet, over every exported row (H19).
  # Formula columns are recalculated from the totals, not summed.
  def add_totals_row(wb, sheet)
    totals = ReportBuilderTotals.new(rows: rows, columns: columns, config: config, scope: :all).call
    return unless totals

    cells = columns.map { |c| formatter.xlsx(totals[c.key], c) }
    # The label goes in the first cell unless that column has a total of its own
    cells[0] = ["Total", nil] if cells.any? && cells[0][0].nil?
    styles = columns.each_with_index.map { |c, i| cell_style(wb, c, cells[i][1], bold: true) }
    sheet.add_row(cells.map(&:first), style: styles)
  end

  # ── Column headers ────────────────────────────────────────────────────────

  def column_headers
    @column_headers ||= columns.map do |col|
      label = (col.label.presence || col.name.to_s).split(";").first.strip
      agg   = header_aggregate(col)
      agg ? "#{label} (#{ReportBuilderColumnType.aggregate_label(agg, config.column_type.base_type(clean_key(col)))})" : label
    end
  end

  # Only many-per-row related columns carry a total in their header
  def header_aggregate(col)
    key = clean_key(col)
    return nil if col.is_a?(ReportBuilderDynamicColumn) || key.exclude?(".")
    return nil if config.column_type.strategy_for(config.column_type.relation_for(key)) == :anchored_one

    config.effective_aggregate(key)
  end

  def clean_key(col)
    col.key.to_s.split(";").first.to_s.strip
  end

  # ── Styles (cached: one style per distinct look, not one per cell) ───────

  def header_style(wb, col)
    style(wb, b: true, bg_color: HEADER_COLOR, fg_color: "FFFFFF",
              alignment: { horizontal: numeric?(col) ? :right : :left })
  end

  def cell_style(wb, col, format_code, alt: false, bold: false)
    opts = { alignment: { horizontal: numeric?(col) ? :right : :left } }
    opts[:format_code] = format_code if format_code
    opts[:bg_color]    = ALT_ROW_COLOR if alt
    opts[:b]           = true if bold
    style(wb, **opts)
  end

  def style(wb, **opts)
    @styles[opts] ||= wb.styles.add_style(opts)
  end

  def numeric?(col)
    formatter.align(col) == "text-end"
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def filter_summary
    parts = config.root_filters.map do |key, val|
      "#{key.to_s.humanize}: #{Array(val).join(', ')}"
    end

    config.joins.each do |join| # rubocop:disable Rails/FindEach -- config.joins is a plain Array, not an AR::Relation
      (join[:child_filters] || {}).each do |key, val|
        parts << "#{join[:relation].to_s.humanize} – #{key.to_s.humanize}: #{Array(val).join(', ')}"
      end
    end

    ts = "Generated: #{I18n.l(Time.current, format: :abbr_date_time)}"
    parts.any? ? "#{ts} | Filters: #{parts.join(' | ')}" : ts
  end

  def col_letter(n)
    return "A" if n <= 0

    result = ""
    while n.positive?
      n, rem = (n - 1).divmod(26)
      result = (65 + rem).chr + result
    end
    result
  end
end
