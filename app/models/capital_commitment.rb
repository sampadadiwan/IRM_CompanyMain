class CapitalCommitment < ApplicationRecord
  belongs_to :entity
  belongs_to :investor
  belongs_to :fund

  monetize :committed_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }
end
