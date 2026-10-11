class PortfolioInvestmentCreate < PortfolioInvestmentAction
  step :set_valuation
  step :validate_currency
  left :handle_currency_errors, Output(:failure) => End(:failure)
  step :compute_amount_cents
  step :setup_aggregate
  left :handle_setup_aggregate_errors, Output(:failure) => End(:failure)
  step :create_valuation
  left :handle_valuation_errors, Output(:failure) => End(:failure)
  step :compute_all_numbers
  step :compute_quantity_as_of_date
  step :save
  left :handle_errors, Output(:failure) => End(:failure), Output(:failure) => End(:failure)
  step :compute_avg_cost
  step :setup_attribution

  # We need to ensure that the currency of the investment_instrument matches the currency of the fund.
  # If it does not, we need to ensure that there is an exchange rate between the two.
  # If there is no exchange rate, we cannot create the PortfolioInvestment and show the error
  def validate_currency(_ctx, portfolio_investment:, **)
    if portfolio_investment.investment_instrument.currency == portfolio_investment.fund.currency
      # If the currencies are the same, we can proceed
      true
    else
      from_currency = portfolio_investment.investment_instrument.currency
      to_currency = portfolio_investment.fund.currency
      fund = portfolio_investment.fund
      # The fund must have an accepted rate on the investment date (its own entity's rates only).
      # X9 — Error case: a manual-only fund with no manual EUR→INR rate is refused, naming its sources.
      policy = SourcePolicy.for(fund)
      as_of = portfolio_investment.investment_date || Time.zone.today
      if FxRateResolver.lookup(entity_id: fund.entity_id, from: from_currency, to: to_currency, as_of:, policy:)
        true
      else
        portfolio_investment.errors.add(:base, FxRateResolver::MissingRate.new(from: from_currency, to: to_currency, as_of:, policy:).message)
        false
      end
    end
  end

  def handle_currency_errors(ctx, portfolio_investment:, **)
    Rails.logger.debug { "PortfolioInvestmentCreate Currency errors: #{portfolio_investment.errors.full_messages}" }
    ctx[:errors] = portfolio_investment.errors.full_messages
    false
  end

  # After we save the PI, we need to create the attributions for sells.
  # When we import the data we create it in the same thread, as we need to ensure the attribution is setup before we move on to the next row. However if the portfolio_investment is created by the user, we can do it in the background.
  # Originally we were doing this in the background, but it was causing issues with the attribution being created in parallel and sometimes in the wrong order.
  def setup_attribution(_ctx, portfolio_investment:, **)
    if portfolio_investment.sell? && !portfolio_investment.proforma
      portfolio_investment.created_by_import ? PortfolioInvestmentJob.perform_now(portfolio_investment.id) : PortfolioInvestmentJob.perform_later(portfolio_investment.id)
    end
    true
  end

  def setup_aggregate(_ctx, portfolio_investment:, **)
    portfolio_investment.setup_aggregate
  end

  # When a new PortfolioInvestment is created, we need to create a new Valuation for it.
  def create_valuation(ctx, portfolio_investment:, **)
    if portfolio_investment.buy?
      investment_instrument_id = portfolio_investment.investment_instrument_id
      investment_date = portfolio_investment.investment_date
      base_cost_cents = portfolio_investment.base_cost_cents
      entity_id = portfolio_investment.entity_id
      portfolio_investment.fund

      # The purchase records a Cost price for its date; it never replaces a Manual or Market price
      # for that date (E40 — Edge case: purchase never overwrites)
      last_valuation = portfolio_investment.portfolio_company.valuations.find_or_initialize_by(
        investment_instrument_id: investment_instrument_id,
        valuation_date: investment_date,
        entity_id: entity_id,
        source: "cost"
      )
      last_valuation.provider = "Purchase"

      last_valuation.per_share_value_cents = base_cost_cents
      ctx[:valuation] = last_valuation
      result = last_valuation.save
      portfolio_investment.valuation = last_valuation if result && portfolio_investment.valuation.blank?
      result
    else
      true
    end
  end

  def handle_valuation_errors(ctx, valuation:, **)
    Rails.logger.debug { "PortfolioInvestmentCreate Valuation errors: #{valuation.errors.full_messages}" }
    ctx[:errors] = valuation.errors.full_messages
    false
  end
end
