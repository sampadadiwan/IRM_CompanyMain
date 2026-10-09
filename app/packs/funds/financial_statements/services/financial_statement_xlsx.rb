# Excel download of a statement set: one sheet per statement (H19), the same rows and columns as the
# screen, amounts as numbers in currency units, and a Checks sheet. Drafts say DRAFT in the title.
# Worked examples H19 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementXlsx
  # Rows printed bold with a rule above
  TOTAL_ROW_TYPES = %w[subtotal net_result opening closing].freeze
  # Parts of the Balance Sheet's "Assets = Liabilities + Partners' capital" line
  BALANCE_LINE_KEYS = %w[assets liabilities capital].freeze

  def initialize(statement)
    @statement = statement
    @fund = statement.fund
  end

  # @return [StringIO]
  def to_stream
    package = Axlsx::Package.new
    workbook = package.workbook
    styles = build_styles(workbook)
    used_names = []
    # One sheet per statement, in the fund's statement order
    @statement.statements.each do |statement_data|
      workbook.add_worksheet(name: sheet_name(statement_data["name"], used_names)) do |sheet|
        write_statement(sheet, statement_data, styles)
      end
    end
    workbook.add_worksheet(name: "Checks") { |sheet| write_checks(sheet, styles) }
    package.to_stream
  end

  private

  def build_styles(workbook)
    {
      title: workbook.styles.add_style(b: true, sz: 14),
      header: workbook.styles.add_style(b: true, alignment: { horizontal: :right }, border: { style: :thin, color: "CCCCCC", edges: [:bottom] }),
      heading: workbook.styles.add_style(b: true),
      amount: workbook.styles.add_style(format_code: "#,##0.00;(#,##0.00)"),
      total: workbook.styles.add_style(b: true, format_code: "#,##0.00;(#,##0.00)", border: { style: :thin, color: "999999", edges: [:top] })
    }
  end

  def write_statement(sheet, statement_data, styles)
    columns = statement_data["columns"]
    # Title block: fund, statement, period, draft marker
    sheet.add_row ["#{@fund.name} — #{statement_data['name']}#{' (DRAFT)' unless @statement.locked?}"], style: styles[:title]
    sheet.add_row ["#{@statement.period_label} · #{@fund.currency}"]
    sheet.add_row []
    # Column headings, with the comparative's source note under each
    sheet.add_row [""] + columns.pluck("label"), style: [nil] + Array.new(columns.size, styles[:header])
    sheet.add_row [""] + columns.map { |c| c["note"].to_s }
    statement_data["rows"].each do |row|
      if row["row_type"] == "heading"
        sheet.add_row [row["label"]], style: styles[:heading]
        next
      end
      # Cents → currency units; totals ruled and bold
      values = columns.map { |c| row["values"][c["key"]].nil? ? nil : (row["values"][c["key"]].to_d / 100).to_f }
      style = TOTAL_ROW_TYPES.include?(row["row_type"]) ? styles[:total] : styles[:amount]
      label = row["row_type"] == "account" ? "    #{row['label']}" : row["label"]
      sheet.add_row [label] + values, style: [row["row_type"] == "account" ? nil : styles[:heading]] + Array.new(columns.size, style)
    end
    # Balance Sheet: the Assets = Liabilities + Partners' capital line, per column
    if statement_data["balance_line"]
      sheet.add_row []
      line_text = columns.map do |c|
        line = statement_data["balance_line"][c["key"]]
        amounts = BALANCE_LINE_KEYS.map { |k| ActiveSupport::NumberHelper.number_to_delimited((line[k].to_d / 100).round(2).to_s("F")) }
        "#{amounts[0]} = #{amounts[1]} + #{amounts[2]} #{line['balanced'] ? '✓' : '✗'}"
      end
      sheet.add_row ["Assets = Liabilities + Partners' capital"] + line_text, style: styles[:heading]
    end
    sheet.column_widths(*([45] + Array.new(columns.size, 22)))
  end

  def write_checks(sheet, styles)
    sheet.add_row ["Checks — #{@statement.period_label}"], style: styles[:title]
    sheet.add_row %w[Check Result Difference Note], style: styles[:heading]
    @statement.checks_list.each do |check|
      diff = check["diff"].nil? ? nil : (check["diff"].to_d / 100).to_f
      sheet.add_row [FinancialStatementCalculator::CHECK_LABELS.fetch(check["key"], check["key"]), check["status"].capitalize, diff, check["note"].to_s],
                    style: [nil, nil, styles[:amount], nil]
    end
    sheet.column_widths 30, 12, 18, 90
  end

  # Excel sheet names: 31 characters, no []:*?/\ and unique
  def sheet_name(name, used)
    base = name.to_s.gsub(%r{[\[\]:*?/\\]}, " ").strip[0, 31].presence || "Statement"
    candidate = base
    n = 2
    while used.include?(candidate.downcase)
      candidate = "#{base[0, 25]} #{n}"
      n += 1
    end
    used << candidate.downcase
    candidate
  end
end
