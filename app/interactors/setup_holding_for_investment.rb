class SetupHoldingForInvestment
  include Interactor

  def call
    Rails.logger.debug "Interactor: SetupHoldingForInvestment called"
    if context.holding.present?
      holding = context.holding
      setup_investment(holding)
    else
      Rails.logger.error "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  private

  def setup_investment(holding)
    Rails.logger.debug "Interactor: SetupHoldingForInvestment.setup_investment  called"

    if Holding::INVESTMENT_FOR.include?(holding.holding_type)

      holding.investment = Investment.for(holding).first
      holding.funding_round_id = holding.option_pool.funding_round_id if holding.option_pool

      if holding.investment.nil?
        Rails.logger.debug { "Creating investment for #{holding.id}" }
        employee_investor = Investor.for(holding.user, holding.entity).first
        investment = Investment.new(investment_type: "#{holding.holding_type} Holdings",
                                    investment_instrument: holding.investment_instrument,
                                    category: holding.holding_type, entity_id: holding.entity.id,
                                    investor_id: employee_investor.id, employee_holdings: true,
                                    quantity: 0, price_cents: holding.price_cents,
                                    currency: holding.entity.currency, funding_round: holding.funding_round,
                                    notes: "Holdings Investment")

        holding.investment = SaveInvestment.call(investment:).investment
      else
        Rails.logger.debug { "Investment already exists for #{holding.id}" }
      end

      holding.save
      create_audit_trail(holding)

    end
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :setup_investment, owner: "Holding", quantity: holding.quantity, operation: :modify, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end
end
