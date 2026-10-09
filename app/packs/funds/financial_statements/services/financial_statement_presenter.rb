# Renders a statement set's statements: for each statement (definition), its columns and its layout
# rows with a value per column. The same structure feeds the screen, Excel, PDF and the frozen copy.
#
# Columns: at-a-date statements show the balance at the end date and at the prior financial
# year-end; period statements show the period, the year to date, and the same year to date last
# year. Prior columns come from the frozen copy of the locked statement set ending on that date
# (flagged when it has drifted); with none, they are computed from current data and headed
# "Not locked — computed".
#
# Values are cents in display sign: expense and liability accounts in brackets (negative);
# subtotals add the displayed values of their rows.
# Worked examples H2, H18, H24, E11, E21 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementPresenter
  # The point a column's opening capital is read at
  OPENING_POINT = { "period" => "opening", "ytd" => "ytd_opening", "balance" => "opening" }.freeze

  def initialize(statement, definitions: nil)
    @statement = statement
    @fund = statement.fund
    # Every statement with its rows and their accounts, loaded once
    @definitions = definitions || FinancialStatementDefinition.where(fund_id: @fund.id).ordered.includes(layout_rows: :account)
    # Account types decide display signs and the capital / net result totals
    @accounts = FinancialStatementCalculator.saved_mapping(@fund).accounts
  end

  def statements
    @definitions.map { |definition| render(definition) }
  end

  # Figure set + note for each column key
  def column_sources
    @column_sources ||= begin
      # Prior year-end (at-date statements) and last year's year to date (period statements)
      prior_ye = comparative(@statement.fy_start - 1, "balance")
      prior_ytd = comparative(@statement.end_date.prev_year, "ytd")
      {
        "balance" => { figures: @statement.figures, key: "balance", label: "As at #{I18n.l(@statement.end_date)}" },
        "prior_year_end" => prior_ye.merge(key: "balance", label: "As at #{I18n.l(@statement.fy_start - 1)}"),
        "period" => { figures: @statement.figures, key: "period", label: @statement.period_label },
        "ytd" => { figures: @statement.figures, key: "ytd", label: "Year to date #{I18n.l(@statement.end_date)}" },
        "prior_ytd" => prior_ytd.merge(key: "ytd", label: "Year to date #{I18n.l(@statement.end_date.prev_year)}")
      }
    end
  end

  private

  # Prior figures ending on date: the locked set's frozen copy, else computed (H18, E11)
  def comparative(date, key)
    # H18: a locked set ending on that date is the published comparative (flagged if it has drifted)
    source = FinancialStatement.locked.where(fund_id: @fund.id, end_date: date).where.not(id: @statement.id).order(:start_date).first
    if source
      note = source.drifted? ? "As locked — changed since locked" : "As locked"
      { figures: source.figures, note:, drifted: source.drifted?, source_id: source.id }
    else
      # E11: no locked source — compute it now and say so in the column heading
      start = key == "ytd" ? @statement.setting.fiscal_year_start(date) : date
      result = FinancialStatementCalculator.call(fund: @fund, start_date: start, end_date: date, setting: @statement.setting)
      { figures: result.figures, note: "Not locked — computed", drifted: false }
    end
  end

  def render(definition)
    # Column headings with their source note ("As locked", "Not locked — computed")
    columns = definition.columns.map { |c| { "key" => c, "label" => column_sources[c][:label], "note" => column_sources[c][:note] } }
    rows = definition.layout_rows.to_a
    values = {}
    # Rows in order; each row's values are kept so later subtotals can add them.
    # H24: an account row reads the same figures on every statement it is placed on
    rendered = rows.map do |row|
      row_values = definition.columns.index_with { |c| row_value(row, rows, values, c) }
      values[row.id] = row_values
      { "row_type" => row.row_type, "label" => row.display_label, "values" => row_values.transform_values { |v| v&.to_s } }
    end
    data = { "definition_id" => definition.id, "name" => definition.name, "kind" => definition.kind,
             "column_style" => definition.column_style, "columns" => columns, "rows" => rendered }
    # The Balance Sheet's foot line: Assets = Liabilities + Partners' capital, per column
    data["balance_line"] = definition.columns.index_with { |c| balance_line(c) } if definition.kind == "balance_sheet"
    data
  end

  # { assets, liabilities, capital, balanced } in cents (liabilities as a positive amount owed)
  def balance_line(column)
    source = column_sources[column]
    figures = source[:figures]
    assets = FinancialStatementCalculator.sum_type(figures, @accounts, "asset", source[:key])
    liabilities = FinancialStatementCalculator.sum_type(figures, @accounts, "liability", source[:key])
    capital = FinancialStatementCalculator.capital_total(figures, @accounts, source[:key])
    # Same one-unit tolerance as the Balance check
    balanced = (assets - liabilities - capital).abs < FinancialStatementCalculator::TOLERANCE_CENTS
    { "assets" => assets.to_s, "liabilities" => liabilities.to_s, "capital" => capital.to_s, "balanced" => balanced }
  end

  def row_value(row, rows, values, column)
    # Which figure set (current / prior) and which figure (period, ytd, balance) this column reads
    source = column_sources[column]
    figures = source[:figures]
    key = source[:key]
    case row.row_type
    when "heading" then nil
    when "account" then display_value(figures, row.financial_statement_account_id, key)
    when "net_result" then FinancialStatementCalculator.net_result(figures, @accounts, key)
    when "opening" then FinancialStatementCalculator.capital_total(figures, @accounts, OPENING_POINT.fetch(key))
    when "closing" then FinancialStatementCalculator.capital_total(figures, @accounts, "balance")
    when "subtotal" then subtotal(row, rows, values, column, figures, key)
    end
  end

  def display_value(figures, account_id, key)
    account = @accounts[account_id]
    return nil unless account

    # Expenses and liabilities print in brackets
    sign = FinancialStatementAccount::NEGATIVE_DISPLAY_TYPES.include?(account["account_type"]) ? -1 : 1
    sign * figures.dig(account_id, key).to_d
  end

  # Adds the referenced rows' displayed values; a heading means every account row in its section
  # (rows after it up to the next heading). Rows are summed in layout order, so a subtotal can use
  # a subtotal above it (Net assets = Total assets + Total liabilities).
  def subtotal(row, rows, values, column, figures, key)
    # H2: adds the displayed values (expenses negative), so Total expenses = (250,000) + (45,200)
    row.subtotal_ids.sum(0.to_d) do |signed_id|
      # A negative id subtracts the row (Total liabilities and partners' capital)
      sign = signed_id.negative? ? -1 : 1
      id = signed_id.abs
      ref = rows.find { |r| r.id == id }
      next 0.to_d unless ref

      value = if ref.row_type == "heading"
                section_rows(ref, rows).sum(0.to_d) { |r| display_value(figures, r.financial_statement_account_id, key).to_d }
              elsif ref.row_type == "subtotal"
                # Only a subtotal above this one (already computed); never recurse, so a cycle can't crash
                values.dig(id, column).to_d
              else
                values.dig(id, column) || row_value(ref, rows, values, column).to_d
              end
      sign * value.to_d
    end
  end

  def section_rows(heading, rows)
    rows[(rows.index(heading) + 1)..].take_while { |r| r.row_type != "heading" }.select { |r| r.row_type == "account" }
  end
end
