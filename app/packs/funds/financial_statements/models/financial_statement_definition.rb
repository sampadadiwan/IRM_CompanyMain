# One statement of a fund: the three core statements (created for every fund, renamable but never
# deletable) and any schedules the fund adds. The layout rows decide what it prints.
# Worked examples H21, H22, H23, X17 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementDefinition < ApplicationRecord
  CORE_KINDS = %w[balance_sheet profit_and_loss changes_in_capital].freeze
  KINDS = (CORE_KINDS + %w[schedule]).freeze
  COLUMN_STYLES = %w[at_date for_period].freeze

  # Default names and fixed column styles of the core statements
  CORE_DEFAULTS = {
    "balance_sheet" => { name: "Balance Sheet", column_style: "at_date", position: 1 },
    "profit_and_loss" => { name: "Profit & Loss", column_style: "for_period", position: 2 },
    "changes_in_capital" => { name: "Statement of Changes in Partners' Capital", column_style: "for_period", position: 3 }
  }.freeze

  # Columns each style prints, in order. Prior columns come from the frozen copy of a locked
  # statement when there is one (see FinancialStatementPresenter).
  COLUMNS = {
    "at_date" => %w[balance prior_year_end],
    "for_period" => %w[period ytd prior_ytd]
  }.freeze

  belongs_to :entity
  belongs_to :fund
  has_many :layout_rows, -> { order(:position, :id) }, class_name: "FinancialStatementLayoutRow",
                                                       dependent: :destroy, inverse_of: :definition

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :fund_id }
  validates :kind, inclusion: { in: KINDS }
  validates :column_style, inclusion: { in: COLUMN_STYLES }
  validate :one_of_each_core_kind
  before_validation :fix_core_column_style
  # X17: core statements can be renamed, not deleted
  before_destroy :refuse_core_destroy

  scope :ordered, -> { order(:position, :id) }

  def core?
    CORE_KINDS.include?(kind)
  end

  def at_date?
    column_style == "at_date"
  end

  def columns
    COLUMNS.fetch(column_style)
  end

  def to_s
    name
  end

  private

  # A core statement's columns follow its kind (the Balance Sheet is always "at a date")
  def fix_core_column_style
    self.column_style = CORE_DEFAULTS[kind][:column_style] if core?
  end

  # MySQL has no partial unique index, so "one balance sheet per fund" is checked here
  def one_of_each_core_kind
    return unless core?

    clash = self.class.where(fund_id:, kind:).where.not(id:)
    errors.add(:kind, "already exists for this fund") if clash.exists?
  end

  def refuse_core_destroy
    # Deleting the fund removes everything, core statements included
    return if destroyed_by_association || !core?

    # X17: core statements are renamable, never deletable
    errors.add(:base, "Core statements can be renamed but not deleted")
    throw(:abort)
  end
end
