# One row of a statement, in order:
#   heading    — section title ("Expenses"); its section is the rows down to the next heading
#   account    — a statement account's figure
#   subtotal   — sum of the rows in subtotal_of (a heading id there means "every row in its section";
#                a negative id subtracts that row, e.g. Total liabilities and partners' capital
#                = closing capital − Total liabilities, which prints in brackets)
#   net_result — the P&L result: for the period on period statements, accumulated since inception on
#                the Balance Sheet (how the P&L closes into partners' capital)
#   opening    — partners' capital at the start of the column's period
#   closing    — partners' capital at the end of the column's period
# Worked examples H2, H3, H24 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementLayoutRow < ApplicationRecord
  ROW_TYPES = %w[heading account subtotal net_result opening closing].freeze
  ROW_TYPE_LABELS = { "heading" => "Heading", "account" => "Account", "subtotal" => "Subtotal",
                      "net_result" => "Net result (from P&L)", "opening" => "Opening partners' capital",
                      "closing" => "Closing partners' capital" }.freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :definition, class_name: "FinancialStatementDefinition", foreign_key: :financial_statement_definition_id,
                          inverse_of: :layout_rows
  belongs_to :account, class_name: "FinancialStatementAccount", foreign_key: :financial_statement_account_id,
                       optional: true, inverse_of: :layout_rows

  validates :row_type, inclusion: { in: ROW_TYPES }
  validates :label, length: { maximum: 150 }
  validates :label, presence: true, if: -> { %w[heading subtotal].include?(row_type) }
  validates :financial_statement_account_id, presence: true, if: -> { row_type == "account" }
  validate :subtotal_rows_in_same_statement
  validate :account_of_same_fund

  # Signed ids: negative = subtract that row
  def subtotal_ids
    Array(subtotal_of).map(&:to_i)
  end

  # The rows referenced, ignoring sign
  def subtotal_row_ids
    subtotal_ids.map(&:abs)
  end

  def subtracts?(row_id)
    subtotal_ids.include?(-row_id)
  end

  def display_label
    label.presence || account&.name || ROW_TYPE_LABELS[row_type]
  end

  private

  def subtotal_rows_in_same_statement
    return unless row_type == "subtotal"

    errors.add(:subtotal_of, "must list at least one row") if subtotal_ids.empty?
    # Sign aside, every referenced row must be on this statement
    foreign = subtotal_row_ids - FinancialStatementLayoutRow.where(financial_statement_definition_id:).pluck(:id)
    errors.add(:subtotal_of, "can only add rows of the same statement") if foreign.any?
    # A subtotal can't include itself (the presenter only reads subtotals above it, so no cycle renders)
    errors.add(:subtotal_of, "can't include the subtotal itself") if id && subtotal_row_ids.include?(id)
  end

  # Tenant safety: an account row points at this fund's accounts only
  def account_of_same_fund
    errors.add(:financial_statement_account_id, "belongs to another fund") if account && account.fund_id != fund_id
  end
end
