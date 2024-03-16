class HoldingAction < Trailblazer::Operation
  def handle_error(ctx, holding:, **)
    Rails.logger.error "Error: #{holding.errors.full_messages.join(', ')}"
    ctx[:errors] = holding.errors.full_messages.join(", ")
  end

  def update_trust_holdings(_ctx, holding:, **)
    if holding.option_pool
      holding.option_pool.reload

      trust_investor = holding.entity.trust_investor
      if  holding.investment_instrument == 'Options' &&
          # This is a hack, when we update the trust investment -> Which updates the holdings -> We dont want it reducing the quantity here. I know I will forget this at sometime in the future.
          holding.investor_id != trust_investor.id &&
          holding.option_pool

        pool_investment = trust_investor.investments.where(
          funding_round_id: holding.option_pool.funding_round_id,
          investment_instrument: 'Options'
        ).first

        pool_investment.quantity = holding.option_pool.available_quantity

        SaveInvestment.call(investment: pool_investment, audit_comment: "Update Trust Holdings").success?
      end
    end
    true
  end
end
