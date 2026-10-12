# Records one event on a contract: checks it (open contract, lots, date), exercises into shares when
# physical, posts the ledger and moves open lots / status — all in one transaction under the
# contract's lock. A repeated idempotency key returns the event already recorded (E51).
# Worked examples H11–H17, E48–E57, X21–X24 — openspec/changes/fund-market-data/business-rules.md
class DerivativeEventRecorder
  Result = Struct.new(:event, :errors, keyword_init: true) do
    def success?
      errors.empty?
    end
  end

  CLOSING = %w[close_out exercise expiry settlement].freeze

  def self.call(contract:, params:, idempotency_key:)
    new(contract, params, idempotency_key).call
  end

  def initialize(contract, params, idempotency_key)
    @contract = contract
    @params = params.to_h.symbolize_keys
    @key = idempotency_key
  end

  def call
    existing = DerivativeEvent.find_by(idempotency_key: @key)
    return Result.new(event: existing, errors: []) if existing

    result = nil
    @contract.with_lock do
      result = record
      raise ActiveRecord::Rollback unless result.success?
    end
    result
  rescue ActiveRecord::RecordNotUnique
    Result.new(event: DerivativeEvent.find_by(idempotency_key: @key), errors: [])
  end

  private

  def record
    event = @contract.derivative_events.build(entity_id: @contract.entity_id, fund_id: @contract.fund_id,
                                              idempotency_key: @key, source: "manual", **@params.slice(*permitted))
    event.event_date ||= Time.zone.today
    errors = guard(event)
    return Result.new(event:, errors:) if errors.any?
    return Result.new(event:, errors: event.errors.full_messages) unless event.valid?

    context = ledger_context(event)
    if event.event_type == "exercise" && physical?
      begin
        event.portfolio_investment = DerivativeExerciser.exercise(@contract, closing_lots(event), event.event_date)
      rescue DerivativeExerciser::InsufficientHolding => e
        return Result.new(event:, errors: [e.message])
      end
    end

    event.lots ||= closing_lots(event) if CLOSING.include?(event.event_type)
    event.save!
    DerivativeLedgerPoster.post(event, context)
    move_lots(event)
    Result.new(event:, errors: [])
  end

  def permitted
    %i[event_type event_date lots amount_cents value_cents delta notes source provider import_upload_id]
  end

  # X22, X23 — Error cases: closed contract; more lots than open
  def guard(event)
    return ["Contract is closed"] if @contract.status == "closed" && event.event_type != "trade"
    return [] unless event.event_type.in?(%w[close_out exercise]) && event.lots.present?

    open = @contract.open_lots.to_d
    event.lots.to_d > open ? ["Only #{format_lots(open)} lots open"] : []
  end

  def physical?
    @contract.settlement == "physical" && @contract.underlying_instrument_id.present?
  end

  # Lots an event closes: the given lots, else all open lots
  def closing_lots(event)
    (event.lots.presence || @contract.open_lots.presence || @contract.lots || 0).to_d
  end

  # Cost and unrealised result of the lots being closed, from the contract before this event
  def ledger_context(event)
    previous = @contract.carrying_value_on(event.event_date)
    context = { previous_carrying_cents: previous, physical: event.event_type == "exercise" && physical? }
    return context unless CLOSING.include?(event.event_type)

    total = @contract.lots.to_d
    open = @contract.open_lots.to_d
    closing = closing_lots(event)
    share_of_total = total.zero? || @contract.swap? ? 1 : closing / total
    share_of_open = open.zero? || @contract.swap? ? 1 : closing / open
    cost_open = @contract.premium_cents.to_d * (total.zero? ? 1 : open / total)
    # Periodic swap settlements don't close anything
    return context.merge(cost_closed_cents: 0, unrealised_closed_cents: 0) if @contract.swap? && event.event_type == "settlement"

    context.merge(cost_closed_cents: @contract.premium_cents.to_d * share_of_total,
                  unrealised_closed_cents: (previous - cost_open) * share_of_open)
  end

  def move_lots(event)
    case event.event_type
    when "close_out", "exercise"
      remaining = @contract.open_lots.to_d - event.lots.to_d
      @contract.update!(open_lots: remaining, status: remaining.positive? ? "open" : "closed")
    when "expiry"
      @contract.update!(open_lots: 0, status: "closed")
    when "settlement"
      # A forward's settlement at maturity closes it; a swap's periodic settlement does not
      @contract.update!(open_lots: 0, status: "closed") unless @contract.swap?
    end
  end

  def format_lots(lots)
    lots == lots.to_i ? lots.to_i.to_s : lots.to_s("F")
  end
end
