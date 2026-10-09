# One row per fund: the financial year the YTD columns use, and which account entries the NAV and
# partners' capital tie-out checks compare against. Blank NAV / capital entries skip that check.
# Worked examples E6, E7, E21 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementSetting < ApplicationRecord
  belongs_to :entity
  belongs_to :fund

  validates :fiscal_year_start_month, inclusion: { in: 1..12 }
  validates :nav_entry_type, :capital_entry_type, length: { maximum: 60 }
  validates :nav_entry_name, :capital_entry_name, length: { maximum: 125 }

  # First day of the financial year that contains date.
  # E21: with an April year, 30 Sep 2026 → 1 Apr 2026; 31 Mar 2026 → 1 Apr 2025.
  def fiscal_year_start(date)
    start = Date.new(date.year, fiscal_year_start_month, 1)
    start > date ? start.prev_year : start
  end

  # The NAV tie-out needs both the entry type and name (E6/E7 skip otherwise)
  def nav_configured?
    nav_entry_type.present? && nav_entry_name.present?
  end

  def capital_configured?
    capital_entry_type.present? && capital_entry_name.present?
  end
end
