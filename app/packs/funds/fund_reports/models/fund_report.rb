class FundReport < ApplicationRecord
  belongs_to :fund
  belongs_to :entity
end
