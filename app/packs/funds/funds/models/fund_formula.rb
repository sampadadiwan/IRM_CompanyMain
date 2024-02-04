class FundFormula < ApplicationRecord
  include ForInvestor
  include Trackable.new

  belongs_to :fund, optional: true
  belongs_to :entity, optional: true
  acts_as_list scope: %i[fund_id], column: :sequence

  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  scope :enabled, -> { where(enabled: true) }
  scope :accounting, -> { where(rule_for: "Accounting") }
  scope :reporting, -> { where(rule_for: "Reporting") }

  validates :name, :entry_type, length: { maximum: 50 }
  validates :rule_type, length: { maximum: 30 }
  validates :commitment_type, length: { maximum: 10 }
  validates :formula, :entry_type, :name, :rule_type, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }

  delegate :to_s, to: :name

  validate :formula_kosher?
  def formula_kosher?
    errors.add(:formula, "You cannot do CRUD operations in a formula") if formula.downcase.match?(/alter|truncate|drop|insert|select|destroy|delete|update|create|save|rollback|system|fork/)
  end

  # Sometimes we just want to sample the commitments to check if all the formulas are ok
  def commitments(sample)
    cc = fund.capital_commitments

    case commitment_type
    when "Pool"
      cc = sample ? cc.pool.limit(10) : cc.pool
    when "CoInvest"
      cc = sample ? cc.co_invest.limit(10) : cc.co_invest
    end
    cc
  end
end
