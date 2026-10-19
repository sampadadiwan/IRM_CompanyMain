# Sends fund-level account entries to a statement account, or excludes them on purpose.
# A rule matches an entry type and, optionally, one exact name; a blank name catches every name of
# that type, including names uploaded later. An exact-name rule beats an any-name rule.
# Worked examples H4, H5, E2 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingRule < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :account, class_name: "FinancialStatementAccount", foreign_key: :financial_statement_account_id,
                       optional: true, inverse_of: :mapping_rules

  validates :entry_type, presence: true, length: { maximum: 60 }
  validates :name, length: { maximum: 125 }, uniqueness: { scope: %i[fund_id entry_type], message: "already has a rule for this entry type" }
  validate :account_xor_excluded
  validate :account_of_same_fund
  normalizes :entry_type, with: ->(value) { value.to_s.strip }
  normalizes :name, with: ->(value) { value.to_s.strip }

  before_validation { self.name ||= "" }

  def any_name?
    name.blank?
  end

  # "Non Deal Expense · Audit Fees" / "Deal Expense · (any name)"
  def key_label
    "#{entry_type} · #{any_name? ? '(any name)' : name}"
  end

  def target_label
    excluded ? "Excluded" : account&.name
  end

  private

  # A rule points at an account, or excludes the entries — never both, never neither
  def account_xor_excluded
    if excluded && financial_statement_account_id.present?
      errors.add(:base, "A rule either excludes the entries or sends them to an account, not both")
    elsif !excluded && financial_statement_account_id.blank?
      errors.add(:financial_statement_account_id, "must be chosen (or mark the rule Excluded)")
    end
  end

  def account_of_same_fund
    errors.add(:financial_statement_account_id, "belongs to another fund") if account && account.fund_id != fund_id
  end
end
