# Makes sure a fund has what its financial statements need, so a fund starts using the feature just
# by saving its first account or its settings:
#   - the settings row (financial year defaulted from the fund's own month_offset_for_fy)
#   - the three core statements, each with a starter layout (sections, totals, net result, capital)
#   - the statement formula (rule type GenerateFinancialStatementLines, tag "Financial Statements")
# Idempotent: find-or-create on unique keys.
# Also places a new account on the right statement under the right heading, so statements are usable
# without any layout work.
# Worked examples H1, H21 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementSetup
  FORMULA_NAME = "Financial Statement Lines".freeze

  # Heading each account type goes under, and the core statement it is placed on
  SECTION_FOR_TYPE = {
    "asset" => %w[balance_sheet Assets],
    "liability" => %w[balance_sheet Liabilities],
    "capital" => ["balance_sheet", "Partners' capital"],
    "income" => ["profit_and_loss", "Investment income"],
    "expense" => %w[profit_and_loss Expenses],
    "gain_loss" => ["profit_and_loss", "Gains and losses"]
  }.freeze

  def self.ensure!(fund)
    new(fund).ensure!
  end

  # An unsaved settings row with the fund's defaults, for previews before setup has run
  def self.default_setting(fund)
    # The fund's own financial year (json_fields month_offset_for_fy, else the geo default)
    month = fund.start_of_financial_year_date(Time.zone.today).month
    FinancialStatementSetting.new(fund:, entity_id: fund.entity_id, fiscal_year_start_month: month)
  end

  def initialize(fund)
    @fund = fund
  end

  def ensure!
    setting = nil
    ActiveRecord::Base.transaction do
      # Each piece is found first, so a second call creates nothing
      setting = FinancialStatementSetting.find_by(fund_id: @fund.id) || self.class.default_setting(@fund).tap(&:save!)
      FinancialStatementDefinition::CORE_DEFAULTS.each_key { |kind| ensure_core_definition(kind) }
      ensure_formula
    end
    setting
  end

  # Puts a new account on its default statement, under its section heading, above that section's
  # total. Capital accounts are also listed on the Changes statement (before the net result row),
  # which is what makes the roll-forward check meaningful.
  def place_account(account)
    # e.g. an expense goes on the P&L under "Expenses"
    kind, heading_label = SECTION_FOR_TYPE.fetch(account.account_type)
    definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, kind:)
    insert_account_row(definition, account, heading_label)
    return unless account.capital?

    # On the Changes statement a capital account sits above the net result row
    changes = FinancialStatementDefinition.find_by!(fund_id: @fund.id, kind: "changes_in_capital")
    insert_before(changes, account_row_attrs(changes, account), changes.layout_rows.find { |r| r.row_type == "net_result" })
  end

  private

  def ensure_core_definition(kind)
    definition = FinancialStatementDefinition.find_by(fund_id: @fund.id, kind:)
    # Already there (possibly renamed): leave it and its layout alone
    return definition if definition

    defaults = FinancialStatementDefinition::CORE_DEFAULTS[kind]
    definition = FinancialStatementDefinition.create!(fund: @fund, entity_id: @fund.entity_id, kind:, name: defaults[:name],
                                                      column_style: defaults[:column_style], position: defaults[:position])
    seed_layout(definition)
    definition
  end

  # Starter layouts. Subtotals over a heading add up that heading's section.
  def seed_layout(definition)
    case definition.kind
    when "balance_sheet"
      assets = add_row(definition, "heading", label: "Assets")
      total_assets = add_row(definition, "subtotal", label: "Total assets", subtotal_of: [assets.id])
      liabilities = add_row(definition, "heading", label: "Liabilities")
      total_liabilities = add_row(definition, "subtotal", label: "Total liabilities", subtotal_of: [liabilities.id])
      add_row(definition, "subtotal", label: "Net assets", subtotal_of: [total_assets.id, total_liabilities.id])
      add_row(definition, "heading", label: "Partners' capital")
      add_row(definition, "net_result", label: "Accumulated net result")
      closing = add_row(definition, "closing", label: "Total partners' capital")
      # Equals Total assets when the statement balances: capital + liabilities (subtracted, as they print
      # in brackets). Lets a reader see Assets = Liabilities + Partners' capital on one line
      add_row(definition, "subtotal", label: "Total liabilities and partners' capital", subtotal_of: [-total_liabilities.id, closing.id])
    when "profit_and_loss"
      income = add_row(definition, "heading", label: "Investment income")
      total_income = add_row(definition, "subtotal", label: "Total income", subtotal_of: [income.id])
      expenses = add_row(definition, "heading", label: "Expenses")
      total_expenses = add_row(definition, "subtotal", label: "Total expenses", subtotal_of: [expenses.id])
      add_row(definition, "subtotal", label: "Net investment income / (loss)", subtotal_of: [total_income.id, total_expenses.id])
      add_row(definition, "heading", label: "Gains and losses")
      add_row(definition, "net_result", label: "Net increase / (decrease) from operations")
    when "changes_in_capital"
      add_row(definition, "opening", label: "Opening partners' capital")
      add_row(definition, "net_result", label: "Net increase / (decrease) from operations")
      add_row(definition, "closing", label: "Closing partners' capital")
    end
  end

  def add_row(definition, row_type, label: nil, subtotal_of: nil)
    # Appended after the statement's last row
    position = (definition.layout_rows.maximum(:position) || 0) + 1
    definition.layout_rows.create!(fund: @fund, entity_id: @fund.entity_id, row_type:, label:, subtotal_of:, position:)
  end

  def ensure_formula
    formula = FundFormula.find_by(fund_id: @fund.id, rule_type: "GenerateFinancialStatementLines")
    # Kept as is if present, even when disabled (Generate then refuses, X15)
    return formula if formula

    # Last in the sequence: statement lines read every other entry. formula "true" is never evaluated
    # (the op computes lines from the mapping) but FundFormula requires one.
    FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: FORMULA_NAME, rule_type: "GenerateFinancialStatementLines",
                        entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE, formula: "true", enabled: true, rule_for: "Accounting",
                        tag_list: FundFormula::FINANCIAL_STATEMENTS_TAG, roll_up: false, generate_ytd_qtly: false,
                        description: "Writes this fund's financial statement lines from its statement mapping. Managed from Financial Statements.")
  end

  def insert_account_row(definition, account, heading_label)
    rows = definition.layout_rows.to_a
    # The section's heading; recreated at the end if the user deleted it
    heading = rows.find { |r| r.row_type == "heading" && r.label == heading_label }
    heading ||= add_row(definition, "heading", label: heading_label).tap { rows = definition.layout_rows.reload.to_a }
    # Stop at the section's total, or the next heading / non-account row after the section
    index = rows.index(heading)
    stop = rows[(index + 1)..].find { |r| r.row_type != "account" }
    insert_before(definition, account_row_attrs(definition, account), stop)
  end

  def account_row_attrs(definition, account)
    { fund: @fund, entity_id: @fund.entity_id, row_type: "account", financial_statement_account_id: account.id,
      financial_statement_definition_id: definition.id }
  end

  # Inserts a row before `stop` (or at the end), shifting later rows down
  def insert_before(definition, attrs, stop)
    position = stop ? stop.position : (definition.layout_rows.maximum(:position) || 0) + 1
    # Make room: every row from the stop row down moves one place
    definition.layout_rows.where(position: position..).update_all("position = position + 1") if stop
    definition.layout_rows.create!(attrs.merge(position:))
  end
end
