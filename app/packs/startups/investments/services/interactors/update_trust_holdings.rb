class UpdateTrustHoldings
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateTrustHoldings called"
    if context.holding.present?
      holding = context.holding
      update_trust_holdings(holding)
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  def update_trust_holdings(holding)
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

      result = SaveInvestment.call(investment: pool_investment, audit_comment: "Update Trust Holdings")
      create_audit_trail(holding, pool_investment) if result.success?
    end
  end

  def create_audit_trail(holding, pool_investment)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :update_trust_holdings, owner: "Investment", quantity: holding.quantity, operation: :subtract, ref: pool_investment, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end
end
