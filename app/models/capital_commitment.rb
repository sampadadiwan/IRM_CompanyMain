class CapitalCommitment < ApplicationRecord
  belongs_to :entity
  belongs_to :investor
  belongs_to :fund
  has_many :capital_remittances, dependent: :destroy

  monetize :committed_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :committed_amount_cents, numericality: { greater_than: 0 }

  counter_culture :fund, column_name: 'committed_amount_cents', delta_column: 'committed_amount_cents'
end
