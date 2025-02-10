class StockConverter < Trailblazer::Operation
  step :validate_currency
  step :create_stock_conversion
  step :adjust_from_portfolio_investment
  step :create_to_portfolio_investment
  step :update_data
  left :handle_errors, Output(:failure) => End(:failure)

  def validate_currency(_ctx, stock_conversion:, **)
    from_currency = stock_conversion.from_instrument.currency
    to_currency = stock_conversion.to_instrument.currency
    from_portfolio_investment = stock_conversion.from_portfolio_investment
    if from_currency != to_currency
      exchange_rate = stock_conversion.entity.exchange_rates.where(from: from_currency, to: to_currency, as_of: ..from_portfolio_investment.investment_date).first
      if exchange_rate.present?
        true
      else
        stock_conversion.errors.add(:base, "No exchange rate found for #{from_currency} to #{to_currency} before #{stock_conversion.conversion_date}")
        return false
      end
    end
    true
  end

  def create_stock_conversion(ctx, stock_conversion:, **)
    ctx[:from_portfolio_investment] = stock_conversion.from_portfolio_investment
    stock_conversion.save
  end

  def adjust_from_portfolio_investment(_ctx, stock_conversion:, from_portfolio_investment:, **)
    from_portfolio_investment.transfer_quantity += stock_conversion.from_quantity
    from_portfolio_investment.notes = stock_conversion.notes
  end

  def create_to_portfolio_investment(ctx, stock_conversion:, **)
    from_portfolio_investment = stock_conversion.from_portfolio_investment
    to_portfolio_investment = PortfolioInvestment.new(entity_id: from_portfolio_investment.entity_id,
                                                      fund_id: from_portfolio_investment.fund_id,
                                                      form_type_id: from_portfolio_investment.form_type_id,
                                                      portfolio_company_id: from_portfolio_investment.portfolio_company_id,
                                                      portfolio_company_name: from_portfolio_investment.portfolio_company_name,
                                                      investment_date: from_portfolio_investment.investment_date,
                                                      quantity: stock_conversion.to_quantity,
                                                      folio_id: from_portfolio_investment.folio_id,
                                                      capital_commitment_id: from_portfolio_investment.capital_commitment_id,
                                                      investment_instrument_id: stock_conversion.to_instrument_id,
                                                      exchange_rate_id: from_portfolio_investment.exchange_rate_id,
                                                      json_fields: from_portfolio_investment.json_fields,
                                                      notes: stock_conversion.notes)

    from_currency = from_portfolio_investment.investment_instrument.currency
    to_currency = to_portfolio_investment.investment_instrument.currency

    ex_expenses_base_amount_cents = to_portfolio_investment.convert_currency(from_currency, to_currency, from_portfolio_investment.base_cost_cents, from_portfolio_investment.investment_date) * stock_conversion.from_quantity
    to_portfolio_investment.ex_expenses_base_amount_cents = ex_expenses_base_amount_cents
    ctx[:to_portfolio_investment] = to_portfolio_investment
  end

  def update_data(_ctx, stock_conversion:, from_portfolio_investment:, to_portfolio_investment:, **)
    from_saved = false
    to_saved = false

    PortfolioInvestment.transaction do
      from_saved = PortfolioInvestmentUpdate.wtf?(portfolio_investment: from_portfolio_investment).success?
      from_portfolio_investment.aggregate_portfolio_investment.reload.save

      to_saved = PortfolioInvestmentCreate.wtf?(portfolio_investment: to_portfolio_investment).success?
      if to_saved
        stock_conversion.to_portfolio_investment = to_portfolio_investment
        stock_conversion.save
      else
        Rails.logger.debug { "create_to_portfolio_investment: #{to_portfolio_investment.errors.full_messages}" }
      end
    end

    from_saved && to_saved
  end

  def handle_errors(ctx, stock_conversion:, **)
    Rails.logger.debug { "handle_errors: #{stock_conversion.errors.full_messages}" }
    ctx[:errors] = stock_conversion.errors
  end
end
