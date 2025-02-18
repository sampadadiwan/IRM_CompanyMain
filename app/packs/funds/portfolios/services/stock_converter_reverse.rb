class StockConverterReverse < Trailblazer::Operation
  step :adjust_from_portfolio_investment
  step :reverse
  left :handle_errors, Output(:failure) => End(:failure)

  def adjust_from_portfolio_investment(_ctx, stock_conversion:, **)
    from_portfolio_investment = stock_conversion.from_portfolio_investment
    from_portfolio_investment.transfer_quantity -= stock_conversion.from_quantity
    from_portfolio_investment.notes = ""
  end

  def reverse(_ctx, stock_conversion:, **)
    from_saved = false
    PortfolioInvestment.transaction do
      stock_conversion.to_portfolio_investment&.destroy
      stock_conversion.destroy
      from_saved = PortfolioInvestmentUpdate.call(portfolio_investment: stock_conversion.from_portfolio_investment).success?
    end
    from_saved
  end

  def handle_errors(ctx, stock_conversion:, **)
    Rails.logger.debug { "handle_errors: #{stock_conversion.errors.full_messages}" }
    ctx[:errors] = stock_conversion.errors
  end
end
