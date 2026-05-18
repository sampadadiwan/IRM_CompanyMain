class FundUnitTransfer < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :from_commitment, class_name: 'CapitalCommitment'
  belongs_to :to_commitment, class_name: 'CapitalCommitment'

  validates :transfer_ratio, numericality: { greater_than: 0, less_than_or_equal_to: 100,
                                             message: "must be between 1 and 100" }
  validates :price,    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :premium,  numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :transfer_date, presence: true
end
