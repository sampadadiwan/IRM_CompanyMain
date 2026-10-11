# A derivative contract held by a fund: option, warrant, future, forward or FX forward (listed or
# OTC) and, in the OTC swaps phase, interest-rate / cross-currency / total-return / credit-default
# swaps. Its value on a date is its latest valuation event on or before that date (contract
# currency); it may be negative (a liability). Ledger entries are posted per event.
# openspec/changes/fund-market-data — design card ⑥. Worked examples H11–H17, E48–E57, X16–X26.
class DerivativeContract < ApplicationRecord
  include Trackable.new

  LISTED_TYPES = %w[option warrant future].freeze
  FORWARD_TYPES = %w[forward fx_forward].freeze
  SWAP_TYPES = %w[irs ccs trs cds].freeze
  TYPES = (LISTED_TYPES + FORWARD_TYPES + SWAP_TYPES).freeze
  TYPE_LABELS = { "option" => "Option", "warrant" => "Warrant", "future" => "Future", "forward" => "Forward",
                  "fx_forward" => "FX forward", "irs" => "Interest-rate swap", "ccs" => "Cross-currency swap",
                  "trs" => "Total-return swap", "cds" => "Credit-default swap" }.freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :underlying_instrument, class_name: "InvestmentInstrument", optional: true
  belongs_to :agreement_document, class_name: "Document", optional: true
  belongs_to :hedge_of, polymorphic: true, optional: true
  has_many :derivative_events, -> { order(:event_date, :id) }, dependent: :destroy, inverse_of: :derivative_contract

  validates :name, presence: true, length: { maximum: 100 }
  validates :contract_type, inclusion: { in: TYPES }
  validates :underlying_type, inclusion: { in: %w[instrument currency_pair index rate credit] }
  validates :side, inclusion: { in: %w[long short] }
  validates :settlement, inclusion: { in: %w[cash physical] }
  validates :status, inclusion: { in: %w[open closed] }
  validates :currency, :trade_date, :expiry_date, presence: true
  validates :option_type, inclusion: { in: %w[call put] }, allow_blank: true
  validate :type_specific_terms

  before_validation :set_defaults, on: :create

  scope :open_contracts, -> { where(status: "open") }

  def type_label
    TYPE_LABELS[contract_type]
  end

  def option?
    contract_type.in?(%w[option warrant])
  end

  def swap?
    contract_type.in?(SWAP_TYPES)
  end

  def long?
    side == "long"
  end

  # Latest valuation (contract currency, signed) on or before the date, or nil
  def value_on(date)
    derivative_events.where(event_type: "valuation", event_date: ..date).reorder(event_date: :desc, id: :desc).pick(:value_cents)&.to_d
  end

  # What the contract is carried at on a date: its latest value, else its premium (cost)
  def carrying_value_on(date)
    value_on(date) || premium_cents.to_d
  end

  # Open on the date: traded by then and not closed by an event on or before it
  def self.open_on(fund, date)
    closed_ids = DerivativeEvent.where(fund_id: fund.id, event_type: %w[expiry close_out exercise settlement], event_date: ..date)
                                .joins(:derivative_contract).where(derivative_contracts: { status: "closed" })
                                .distinct.pluck(:derivative_contract_id)
    where(fund_id: fund.id, trade_date: ..date).where.not(id: closed_ids)
  end

  # { assets_cents:, liabilities_cents:, missing: [contracts] } in fund currency on the date —
  # the open-ended NAV reads this (design › Bridge). A value of exactly zero adds to neither.
  def self.value_on(fund, date)
    policy = SourcePolicy.for(fund)
    open_on(fund, date).each_with_object({ assets_cents: 0.to_d, liabilities_cents: 0.to_d, missing: [] }) do |contract, totals|
      value = contract.value_on(date)
      if value.nil?
        totals[:missing] << contract
        next
      end
      rate = FxRateResolver.resolve(entity_id: fund.entity_id, from: contract.currency, to: fund.currency, as_of: date, policy:).rate
      fund_value = value * rate.to_d
      totals[:assets_cents] += fund_value if fund_value.positive?
      totals[:liabilities_cents] += fund_value.abs if fund_value.negative?
    end
  end

  # Holding line: "FX forward, sell USD 1,00,000 @ 84.00"
  def summary
    case contract_type
    when "fx_forward", "forward"
      "#{type_label}, #{long? ? 'buy' : 'sell'} #{underlying_name.to_s.split('/').first} #{format_amount(notional_cents)} @ #{format('%.2f', forward_rate.to_d)}"
    else
      name
    end
  end

  private

  def format_amount(cents)
    major = (cents.to_d / 100).round(2)
    ActiveSupport::NumberHelper.number_to_delimited(major == major.to_i ? major.to_i : major)
  end

  def set_defaults
    self.open_lots ||= lots
    self.status ||= "open"
  end

  # X14, X19, X20, X26 — required terms depend on the type
  def type_specific_terms
    if option?
      %i[strike lot_size lots option_type].each { |attr| errors.add(attr, "can't be blank") if self[attr].blank? }
    elsif contract_type == "future"
      %i[lot_size lots].each { |attr| errors.add(attr, "can't be blank") if self[attr].blank? }
    elsif contract_type.in?(FORWARD_TYPES)
      %i[notional_cents forward_rate].each { |attr| errors.add(attr == :notional_cents ? :notional : attr, "can't be blank") if self[attr].blank? }
    elsif swap?
      errors.add(:notional, "can't be blank") if notional_cents.blank?
      errors.add(:agreement, "can't be blank") if agreement_document_id.blank?
    end
    errors.add(:underlying, "can't be blank") if underlying_instrument_id.blank? && underlying_name.blank?
    errors.add(:counterparty, "can't be blank") if !listed && counterparty_name.blank?
    errors.add(:expiry_date, "must be on or after the trade date") if trade_date && expiry_date && expiry_date < trade_date
  end
end
