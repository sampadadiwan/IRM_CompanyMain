# Fund › Derivatives: list, record and view contracts, and add events to them.
# openspec/changes/fund-market-data — design card ⑥ (routes). Worked examples H11–H16, E48–E55, X16–X25.
class DerivativeContractsController < ApplicationController
  before_action :set_fund, only: %i[index new create]
  before_action :set_contract, only: %i[show edit update record_event]

  def index
    authorize(DerivativeContract.new(fund: @fund, entity_id: @fund.entity_id), :show?)
    @status = params[:status].presence_in(%w[open closed all]) || "open"
    @contracts = policy_scope(DerivativeContract).where(fund_id: @fund.id).order(:expiry_date)
    @contracts = @contracts.where(status: @status) unless @status == "all"
    @bread_crumbs = { Funds: funds_path, @fund.name => fund_path(@fund), Derivatives: nil }
    # The fund's Portfolio tab loads open contracts into a frame of its own
    render :portfolio_section if params[:embedded].present?
  end

  def show
    @bread_crumbs = { Funds: funds_path, @contract.fund.name => fund_path(@contract.fund),
                      Derivatives: fund_derivative_contracts_path(@contract.fund), @contract.name => nil }
    @event = @contract.derivative_events.build(event_date: Time.zone.today)
  end

  def new
    @contract = DerivativeContract.new(fund: @fund, entity_id: @fund.entity_id, currency: @fund.currency, trade_date: Time.zone.today,
                                       side: "long", listed: true, underlying_type: "instrument", settlement: "cash")
    authorize(@contract)
  end

  def create
    @contract = DerivativeContract.new(contract_params.merge(fund: @fund, entity_id: @fund.entity_id))
    authorize(@contract)
    if DerivativeContractCreator.call(contract: @contract, premium: params.dig(:derivative_contract, :premium))
      redirect_to derivative_contract_path(@contract), notice: "Contract recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  # Terms only; money moves through events
  def update
    if @contract.update(contract_params.except(:contract_type, :side, :lots, :trade_date))
      redirect_to derivative_contract_path(@contract), notice: "Contract updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /derivative_contracts/:id/record_event — any event (valuation, settlement, margin,
  # exercise, expiry, close-out); idempotency key from the form token prevents double submits (E51)
  def record_event
    authorize(@contract, :record_event?)
    attrs = event_params
    result = DerivativeEventRecorder.call(contract: @contract, idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid,
                                          params: attrs)
    if result.success?
      redirect_to derivative_contract_path(@contract), notice: "#{result.event.type_label} recorded."
    else
      redirect_to derivative_contract_path(@contract), alert: result.errors.to_sentence
    end
  end

  private

  def set_fund
    @fund = Fund.find(params[:fund_id])
  end

  def set_contract
    @contract = DerivativeContract.find(params[:id])
    authorize(@contract) unless action_name == "record_event"
  end

  def contract_params
    permitted = params.require(:derivative_contract).permit(
      :name, :contract_type, :listed, :exchange, :feed_symbol, :counterparty_name, :agreement_document_id,
      :underlying_type, :underlying_instrument_id, :underlying_name, :side, :option_type, :strike, :forward_rate,
      :lots, :lot_size, :notional, :currency, :trade_date, :expiry_date, :settlement, :hedge_of_id, :hedge_unit_type
    )
    # Linked records must belong to this fund / entity — never another tenant's ids
    fund = @fund || @contract.fund
    permitted[:hedge_of_id] = nil if permitted[:hedge_of_id].present? &&
                                     !AggregatePortfolioInvestment.exists?(id: permitted[:hedge_of_id], fund_id: fund.id)
    permitted[:underlying_instrument_id] = nil if permitted[:underlying_instrument_id].present? &&
                                                  !InvestmentInstrument.exists?(id: permitted[:underlying_instrument_id], entity_id: fund.entity_id)
    permitted[:agreement_document_id] = nil if permitted[:agreement_document_id].present? &&
                                               !Document.exists?(id: permitted[:agreement_document_id], entity_id: fund.entity_id)
    # Hedged holding is an aggregate portfolio investment of this fund
    permitted[:hedge_of_type] = permitted[:hedge_of_id].present? ? "AggregatePortfolioInvestment" : nil
    notional = permitted.delete(:notional)
    permitted[:notional_cents] = BigDecimal(notional) * 100 if notional.present?
    permitted
  end

  # Amounts are entered in major units; amount is cash (+ received / − paid), value is signed
  def event_params
    p = params.require(:derivative_event).permit(:event_type, :event_date, :lots, :amount, :value, :delta, :notes, :provider)
    attrs = p.to_h.except("amount", "value")
    attrs["amount_cents"] = BigDecimal(p[:amount]) * 100 if p[:amount].present?
    attrs["value_cents"] = BigDecimal(p[:value]) * 100 if p[:value].present?
    attrs["source"] = "upload" if p[:event_type] == "valuation" && p[:provider].present?
    attrs.compact_blank
  end
end
