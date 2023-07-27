class AllocationRun < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :user
end
