class FundRatio < ApplicationRecord
  include Trackable

  belongs_to :entity
  belongs_to :fund
  belongs_to :valuation
end
