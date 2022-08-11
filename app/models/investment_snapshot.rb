class InvestmentSnapshot < ApplicationRecord
  belongs_to :investor
  belongs_to :entity
  belongs_to :funding_round
  belongs_to :investment
end
