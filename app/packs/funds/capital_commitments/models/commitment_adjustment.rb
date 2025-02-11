class CommitmentAdjustment < ApplicationRecord
  include WithExchangeRate
  include ForInvestor
  include Trackable.new(associated_with: :owner)

  ADJUSTMENT_TYPES = ["Top Up", "Arrear", "Exchange Rate"].freeze
  ADJUST_COMMITMENT_TYPES = ["Top Up", "Exchange Rate"].freeze
  ADJUST_ARREAR_TYPES = ["Arrear"].freeze

  scope :top_up, -> { where(adjustment_type: "Top Up") }
  scope :arrear, -> { where(adjustment_type: "Arrear") }
  scope :exchange_rate, -> { where(adjustment_type: "Exchange Rate") }

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment
  belongs_to :owner, polymorphic: true, optional: true

  validates :reason, :as_of, :folio_amount_cents, :adjustment_type, presence: true
  validate :validate_as_of
  validates :adjustment_type, length: { maximum: 20 }
  validates :adjustment_type, inclusion: { in: ADJUSTMENT_TYPES }

  monetize :tracking_amount_cents, with_currency: ->(i) { i.fund.tracking_currency }
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }
  monetize :amount_cents, :pre_adjustment_cents, :post_adjustment_cents, with_currency: ->(i) { i.fund.currency }

  # Roll up tracking adjustment amount to capital commitment for "Top Up" and "Exchange Rate" types
  counter_culture :capital_commitment, column_name: proc { |r| r.update_committed_amounts? ? 'tracking_adjustment_amount_cents' : nil },
                                       delta_column: 'tracking_amount_cents',
                                       column_names: {
                                         ["commitment_adjustments.adjustment_type in (?)", ADJUST_COMMITMENT_TYPES] => 'tracking_adjustment_amount_cents'
                                       },
                                       execute_after_commit: true

  # Roll up adjustment amount to capital commitment for "Top Up" and "Exchange Rate" types
  counter_culture :capital_commitment, column_name: proc { |r| r.update_committed_amounts? ? 'adjustment_amount_cents' : nil },
                                       delta_column: 'amount_cents',
                                       column_names: {
                                         ["commitment_adjustments.adjustment_type in (?)", ADJUST_COMMITMENT_TYPES] => 'adjustment_amount_cents'
                                       },
                                       execute_after_commit: true

  # Roll up adjustment folio amount to capital commitment for "Top Up" and "Exchange Rate" types
  counter_culture :capital_commitment, column_name: proc { |r| r.update_committed_amounts? ? 'adjustment_folio_amount_cents' : nil },
                                       delta_column: 'folio_amount_cents',
                                       column_names: {
                                         ["commitment_adjustments.adjustment_type in (?)", ADJUST_COMMITMENT_TYPES] => 'adjustment_folio_amount_cents'
                                       },
                                       execute_after_commit: true

  # Roll up arrear amount to capital commitment for "Arrear" type
  counter_culture :capital_commitment, column_name: proc { |r| r.update_arrear_amounts? ? 'arrear_amount_cents' : nil },
                                       delta_column: 'amount_cents',
                                       column_names: {
                                         ["commitment_adjustments.adjustment_type in (?)", ADJUST_ARREAR_TYPES] => 'arrear_amount_cents'
                                       },
                                       execute_after_commit: true

  # Roll up arrear folio amount to capital commitment for "Arrear" type
  counter_culture :capital_commitment, column_name: proc { |r| r.update_arrear_amounts? ? 'arrear_folio_amount_cents' : nil },
                                       delta_column: 'folio_amount_cents',
                                       column_names: {
                                         ["commitment_adjustments.adjustment_type in (?)", ADJUST_ARREAR_TYPES] => 'arrear_folio_amount_cents'
                                       },
                                       execute_after_commit: true

  # Roll up arrear amount to owner for "Arrear" type
  counter_culture :owner, column_name: proc { |r| r.update_arrear_amounts? ? 'arrear_amount_cents' : nil },
                          delta_column: 'amount_cents',
                          column_names: {
                            ["commitment_adjustments.adjustment_type in (?)", ADJUST_ARREAR_TYPES] => 'arrear_amount_cents'
                          },
                          execute_after_commit: true

  # Roll up arrear folio amount to owner for "Arrear" type
  counter_culture :owner, column_name: proc { |r| r.update_arrear_amounts? ? 'arrear_folio_amount_cents' : nil },
                          delta_column: 'folio_amount_cents',
                          column_names: {
                            ["commitment_adjustments.adjustment_type in (?)", ADJUST_ARREAR_TYPES] => 'arrear_folio_amount_cents'
                          },
                          execute_after_commit: true

  def update_committed_amounts
    logger.debug "Updating committed amounts for #{capital_commitment.folio_id}"
    # Convert
    if folio_amount_cents != 0
      self.amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency,
                                           folio_amount_cents, as_of)
    end
    # Update Pre/Post
    self.pre_adjustment_cents = capital_commitment.committed_amount_cents
    self.post_adjustment_cents = amount_cents + pre_adjustment_cents
  end

  def update_arrear_amounts
    logger.debug "Updating arrear amounts for #{capital_commitment.folio_id}"
    # Convert
    if folio_amount_cents != 0
      self.amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency,
                                           folio_amount_cents, as_of)
    end
    # Update Pre/Post
    self.pre_adjustment_cents = capital_commitment.arrear_amount_cents
    self.post_adjustment_cents = amount_cents + pre_adjustment_cents
  end

  def update_committed_amounts?
    ADJUST_COMMITMENT_TYPES.include? adjustment_type
  end

  def update_arrear_amounts?
    ADJUST_ARREAR_TYPES.include? adjustment_type
  end

  after_destroy -> { CapitalCommitmentUpdate.call(capital_commitment: capital_commitment.reload) }

  def to_s
    "CommitmentAdjustment: #{capital_commitment.folio_id}, #{folio_amount}, #{amount}, #{owner}"
  end

  def validate_as_of
    errors.add(:as_of, "must be on or after the commitment date") if as_of < capital_commitment.commitment_date
  end

  def tracking_exchange_rate_date
    as_of
  end
end
