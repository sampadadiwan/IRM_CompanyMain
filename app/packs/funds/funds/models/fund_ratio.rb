class FundRatio < ApplicationRecord
  include Trackable

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment, optional: true
  belongs_to :valuation, optional: true
end
