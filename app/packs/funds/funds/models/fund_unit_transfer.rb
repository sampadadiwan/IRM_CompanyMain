class FundUnitTransfer < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :from_commitment, class_name: 'CapitalCommitment'
  belongs_to :to_commitment, class_name: 'CapitalCommitment'
end
