class ReportBuilderXlsxExporter
  HEADER_COLOR  = "2D5BA3".freeze
  ALT_ROW_COLOR = "F0F4F8".freeze

  def initialize(report:, rows:, columns: nil)
    @report  = report
    @rows    = rows
    @config  = ReportBuilderConfig.new(report.template)
    @columns = columns || report.grid_view_preferences.reorder(:sequence, :id).to_a
  end

  # Returns raw xlsx binary string.
  def generate
    package = Axlsx::Package.new
    wb      = package.workbook

    add_data_sheet(wb)
    add_totals_sheet(wb) if any_numeric_aggregates?

    package.to_stream.read
  end

  private

  attr_reader :report, :rows, :config, :columns

  # ── Sheets ───────────────────────────────────────────────────────────────

  def add_data_sheet(wb)
    wb.add_worksheet(name: "Data") do |sheet|
      col_count = columns.length

      # Row 1: report name
      sheet.add_row [report.name], style: [wb.styles.add_style(b: true, sz: 13)]
      sheet.merge_cells("A1:#{col_letter(col_count)}1") if col_count > 1

      # Row 2: filter summary
      sheet.add_row [filter_summary], style: [wb.styles.add_style(sz: 9, fg_color: "888888")]
      sheet.merge_cells("A2:#{col_letter(col_count)}2") if col_count > 1

      # Row 3: headers
      header_styles = columns.map { |gvp| header_style(wb, gvp) }
      sheet.add_row(column_headers, style: header_styles)
      sheet.sheet_view.pane do |p|
        p.top_left_cell = "A4"
        p.state         = :frozen
        p.y_split       = 3
      end
      sheet.auto_filter = "A3:#{col_letter(col_count)}3"

      # Data rows
      current_group = nil
      group_col = config.group_rows_by

      # Sort rows by group if grouping is enabled
      sorted_rows = if group_col.present?
                      rows.sort_by { |r| r[group_col].to_s }
                    else
                      rows
                    end

      sorted_rows.each_with_index do |row_data, idx|
        if group_col.present?
          group_val = row_data[group_col].to_s
          if group_val != current_group
            # Add a group header row
            sheet.add_row [group_val], style: bold_style(wb)
            sheet.merge_cells("A#{sheet.rows.size}:#{col_letter(col_count)}#{sheet.rows.size}")
            current_group = group_val
          end
        end

        values = columns.map { |gvp| formatted_value(row_data[gvp.key], gvp) }
        styles = columns.map { |gvp| data_style(wb, gvp, idx) }

        row_opts = {}
        row_opts[:outline_level] = 1 if group_col.present?

        sheet.add_row(values, style: styles, **row_opts)
      end

      # Auto-fit column widths (sample first 200 rows + header)
      columns.each_with_index do |gvp, i|
        sample = [column_headers[i].to_s] +
                 rows.first(200).map { |r| formatted_value(r[gvp.key], gvp).to_s }
        sheet.column_info[i].width = [sample.map(&:length).max.to_i + 2, 8].max
      end
    end
  end

  def add_totals_sheet(wb)
    wb.add_worksheet(name: "Totals") do |sheet|
      sheet.add_row(column_headers, style: columns.map { |gvp| header_style(wb, gvp) })

      totals = columns.map do |gvp|
        agg = config.aggregate_for(gvp.key.split(";").first.strip)
        %w[sum count].include?(agg) ? rows.sum { |r| r[gvp.key].to_f } : nil
      end

      sheet.add_row(totals)
    end
  end

  # ── Column headers ────────────────────────────────────────────────────────

  def column_headers
    columns.map do |gvp|
      label = (gvp.label.presence || gvp.name.to_s).split(";").first.strip
      agg   = config.aggregate_for(gvp.key.split(";").first.strip)
      agg ? "#{label} (#{agg})" : label
    end
  end

  # ── Styles ───────────────────────────────────────────────────────────────

  def header_style(wb, gvp)
    wb.styles.add_style(
      b: true,
      bg_color: HEADER_COLOR,
      fg_color: "FFFFFF",
      alignment: { horizontal: numeric_col?(gvp) ? :right : :left }
    )
  end

  def data_style(wb, gvp, row_idx)
    opts = { alignment: { horizontal: numeric_col?(gvp) ? :right : :left } }
    opts[:format_code] = "#,##0.00" if numeric_col?(gvp)
    opts[:bg_color]    = ALT_ROW_COLOR if row_idx.odd?
    wb.styles.add_style(opts)
  end

  def bold_style(wb)
    wb.styles.add_style(b: true, sz: 13)
  end

  # ── Value formatting ──────────────────────────────────────────────────────

  def formatted_value(val, gvp)
    return nil if val.nil?

    case gvp.data_type&.downcase
    when "date"     then val.respond_to?(:strftime) ? val.strftime("%d-%b-%Y") : val.to_s
    when "datetime" then val.respond_to?(:strftime) ? val.strftime("%d-%b-%Y %H:%M") : val.to_s
    when "boolean"  then val ? "Yes" : "No"
    else            val
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def numeric_col?(gvp)
    gvp.data_type.to_s.in?(%w[Decimal Float Integer decimal float integer]) ||
      gvp.key.to_s.include?("num-col") ||
      gvp.key.to_s.include?("__pivot__")
  end

  def any_numeric_aggregates?
    columns.any? do |gvp|
      agg = config.aggregate_for(gvp.key.split(";").first.strip)
      %w[sum count avg].include?(agg)
    end
  end

  def filter_summary
    parts = config.root_filters.map do |key, val|
      "#{key.to_s.humanize}: #{Array(val).join(', ')}"
    end

    config.joins.each do |join| # rubocop:disable Rails/FindEach -- config.joins is a plain Array, not an AR::Relation
      (join[:child_filters] || {}).each do |key, val|
        parts << "#{join[:relation].to_s.humanize} – #{key.to_s.humanize}: #{Array(val).join(', ')}"
      end
    end

    ts = "Generated: #{Time.current.strftime('%d-%b-%Y %H:%M')}"
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
