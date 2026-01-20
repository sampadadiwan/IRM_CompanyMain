module CommitmentAdjustmentShared
  extend ActiveSupport::Concern

  ADJUSTMENT_TYPES = ["Top Up", "Arrear", "Exchange Rate", "Transfer"].freeze
  ADJUST_COMMITMENT_TYPES = ["Top Up", "Exchange Rate", "Transfer"].freeze
  ADJUST_ARREAR_TYPES = ["Arrear"].freeze

  included do
    scope :top_up, -> { where(adjustment_type: "Top Up") }
    scope :arrear, -> { where(adjustment_type: "Arrear") }
    scope :transfer, -> { where(adjustment_type: "Transfer") }
    scope :exchange_rate, -> { where(adjustment_type: "Exchange Rate") }
    scope :for_type, ->(type) { where(adjustment_type: type) }

    monetize :tracking_amount_cents, with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }
    monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }
    monetize :amount_cents, :pre_adjustment_cents, :post_adjustment_cents, with_currency: ->(i) { i.fund.currency }
  end

  def update_committed_amounts?
    ADJUST_COMMITMENT_TYPES.include? adjustment_type
  end

  def update_arrear_amounts?
    ADJUST_ARREAR_TYPES.include? adjustment_type
  end

  def to_s
    "CommitmentAdjustment: #{capital_commitment.folio_id}, #{folio_amount}, #{amount}, #{owner}"
  end
end
