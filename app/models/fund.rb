class Fund < ApplicationRecord
  belongs_to :entity
  monetize :committed_amount_cents, :collected_amount_cents
end
