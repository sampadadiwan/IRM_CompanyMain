# Posts a derivative event to the fund ledger (fund-level AccountEntry rows, entry type
# "Derivatives", parent = the event — one row per event and name, so a repeat is harmless).
#
#   trade      → "Derivative Premium"              cash: −premium paid / +premium received
#   valuation  → "Derivative Unrealised Gain/Loss"  new value − previous carrying value
#   settlement / close-out / expiry / cash exercise
#              → "Derivative Settlement"            cash received (+) or paid (−)
#              → "Derivative Realised Gain/Loss"    cash − cost of the closed lots
#              → "Derivative Unrealised Gain/Loss"  reverses the closed lots' unrealised
#   margin     → "Derivative Margin"                −posted / +returned
#
# Amounts are converted to the fund's currency with the rate the fund accepts on the event date.
# Worked examples H11, H13, E48–E50, E54, H17 — openspec/changes/fund-market-data/business-rules.md
class DerivativeLedgerPoster
  ENTRY_TYPE = "Derivatives".freeze

  def self.post(event, context = {})
    new(event, context).post
  end

  # context: { previous_carrying_cents:, cost_closed_cents:, unrealised_closed_cents: } worked out by
  # DerivativeEventRecorder before it changes the contract
  def initialize(event, context)
    @event = event
    @contract = event.derivative_contract
    @context = context
  end

  def post
    case @event.event_type
    when "trade"
      entry("Derivative Premium", @event.amount_cents)
    when "valuation"
      entry("Derivative Unrealised Gain/Loss", @event.value_cents.to_d - @context.fetch(:previous_carrying_cents).to_d)
    when "margin"
      entry("Derivative Margin", @event.amount_cents)
    when "settlement", "close_out", "expiry", "exercise"
      post_closing
    end
  end

  private

  def post_closing
    cash = @event.amount_cents.to_d
    entries = []
    entries << entry("Derivative Settlement", cash) unless cash.zero?
    # Physical exercise moves the premium into the share's cost — no realised result
    entries << entry("Derivative Realised Gain/Loss", cash - @context.fetch(:cost_closed_cents).to_d) unless @context[:physical]
    reversal = -@context.fetch(:unrealised_closed_cents, 0).to_d
    entries << entry("Derivative Unrealised Gain/Loss", reversal) unless reversal.zero?
    entries.compact
  end

  def entry(name, contract_amount_cents)
    amount = contract_amount_cents.to_d
    # H12 — nothing to post (e.g. a forward has no premium)
    return nil if amount.zero?

    AccountEntry.find_or_create_by!(fund_id: @contract.fund_id, entity_id: @contract.entity_id, parent: @event, name:,
                                    entry_type: ENTRY_TYPE, reporting_date: @event.event_date) do |ae|
      ae.amount_cents = to_fund_currency(amount)
      ae.notes = "#{@contract.name} — #{@event.type_label}"
    end
  end

  def to_fund_currency(amount)
    fund = @contract.fund
    return amount if @contract.currency == fund.currency

    rate = FxRateResolver.resolve(entity_id: fund.entity_id, from: @contract.currency, to: fund.currency,
                                  as_of: @event.event_date, policy: SourcePolicy.for(fund)).rate
    (amount * rate.to_d).round(2)
  end
end
