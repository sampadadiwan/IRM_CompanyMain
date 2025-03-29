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

  def self.ransackable_attributes(_auth_object = nil)
    %w[end_date fund_ratios generate_soa locked start_date status tag_list template_name user_id].sort
  end
end
