class CapitalCall < ApplicationRecord
  belongs_to :entity
  belongs_to :fund

  validates :name, :due_date, :percentage_called, presence: true
  validates :percentage_called, numericality: { in: 0..100 }

  monetize :due_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }
end
