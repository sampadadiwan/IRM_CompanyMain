# Physically settled exercise: a call (or long future) creates the share purchase at the strike
# plus the premium per share; a put creates the sale at the strike, refused when the fund holds
# fewer shares. Uses the existing purchase flow so cost basis, attribution and aggregates follow.
# Worked examples H15, E53, X24 — openspec/changes/fund-market-data/business-rules.md
class DerivativeExerciser
  class InsufficientHolding < StandardError; end

  def self.exercise(contract, lots, date)
    new(contract, lots, date).exercise
  end

  def initialize(contract, lots, date)
    @contract = contract
    @lots = lots.to_d
    @date = date
  end

  def exercise
    instrument = @contract.underlying_instrument
    qty = @lots * @contract.lot_size.to_d
    buying = @contract.contract_type == "future" ? @contract.long? : @contract.option_type == "call"
    price = buying ? @contract.strike.to_d + premium_per_share : @contract.strike.to_d
    check_holding!(instrument, qty) unless buying

    pi = PortfolioInvestment.new(entity_id: @contract.entity_id, fund_id: @contract.fund_id, investment_instrument: instrument,
                                 portfolio_company: instrument.portfolio_company, investment_date: @date,
                                 quantity: buying ? qty : -qty, ex_expenses_base_amount_cents: (qty * price * 100).round(2),
                                 category: instrument.category, sub_category: instrument.sub_category, sector: instrument.sector,
                                 notes: "Exercise of #{@contract.name}")
    result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
    raise ActiveRecord::RecordInvalid, pi unless result.success?

    pi
  end

  private

  # Premium per underlying share, in the contract currency (major units)
  def premium_per_share
    total_shares = @contract.lots.to_d * @contract.lot_size.to_d
    total_shares.zero? ? 0 : (@contract.premium_cents.to_d / 100 / total_shares)
  end

  # X24 — Error case: a physical put needs the shares
  def check_holding!(instrument, qty)
    api = AggregatePortfolioInvestment.find_by(fund_id: @contract.fund_id, investment_instrument_id: instrument.id)
    held = api ? api.net_quantity_on(@date) : 0
    return if held >= qty

    raise InsufficientHolding, "Fund holds only #{held.to_d.to_i} shares of #{instrument.name}"
  end
end
