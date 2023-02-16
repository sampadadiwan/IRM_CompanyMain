class FundFormula < ApplicationRecord
  belongs_to :fund
  belongs_to :entity
  acts_as_list scope: %i[fund_id], column: :sequence

  scope :enabled, -> { where(enabled: true) }

  delegate :to_s, to: :name
end
