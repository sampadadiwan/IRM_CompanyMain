class TickerFeed < ApplicationRecord
  validates :ticker, presence: true
  validates :name, presence: true
  validates :source, presence: true
  validates :for_date, presence: true
  validates :for_time, presence: true
  validates :price_type, presence: true
  validates :currency, presence: true
  validates :price_type, inclusion: { in: %w[ID EOD] }

  monetize :price_cents, with_currency: ->(i) { i.currency }
end
