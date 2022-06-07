class CreateAggregateInvestment
  include Interactor

  def call
    Rails.logger.debug "Interactor: CreateAggregateInvestment called"
    if context.investment
      create_aggregate_investment(context.investment)
    else
      Rails.logger.debug "No investment specified"
      context.fail!(message: "No investment specified")
    end
  end

  def create_aggregate_investment(investment)
    if Investment::EQUITY_LIKE.include?(investment.investment_instrument)

      ai = AggregateInvestment.where(investor_id: investment.investor_id,
                                     entity_id: investment.investee_entity_id).first

      investment.aggregate_investment = ai.presence ||
                                        AggregateInvestment.create!(investor_id: investment.investor_id,
                                                                    entity_id: investment.investee_entity_id,
                                                                    audit_comment: context.audit_comment)

      create_audit_trail(investment)
    end
  end

  def create_audit_trail(investment)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :create_aggregate_investment, owner: "Investment", quantity: investment.quantity, operation: :modify, ref: investment.aggregate_investment, entity_id: investment.investee_entity_id, completed: true, parent_id: context.parent_id)
  end
end
