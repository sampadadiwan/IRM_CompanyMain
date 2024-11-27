class AllocationRun < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :user

  scope :locked, -> { where(locked: true) }

  def self.locked_and_overlapping(fund_id, start_date, end_date)
    where(fund_id:)
      .locked
      .where("start_date <= ? AND end_date >= ?", end_date, start_date)
      .first
  end
end
