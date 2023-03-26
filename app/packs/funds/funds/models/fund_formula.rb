class FundFormula < ApplicationRecord
  belongs_to :fund
  belongs_to :entity
  acts_as_list scope: %i[fund_id], column: :sequence

  scope :enabled, -> { where(enabled: true) }

  delegate :to_s, to: :name

  before_save :sanitize_name
  def sanitize_name
    self.name = name.strip
  end

  validate :formula_kosher?
  def formula_kosher?
    errors.add(:formula, "You cannot do CRUD operations in a formula") if formula.downcase.match?(/destroy|delete|update|create|save|rollback/)
  end

  def commitments
    cc = fund.capital_commitments

    case commitment_type
    when "Pool"
      cc = cc.pool
    when "CoInvest"
      cc = cc.co_invest
    end
    cc
  end
end
