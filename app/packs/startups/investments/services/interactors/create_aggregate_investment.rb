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

      funding_round_id = if investment.investment_instrument == "Units"
                           # Funding round applies only to Investment Funds aggregate investments.
                           # This is because in investment funds, the investors may be invested across multiple Funds
                           # Aggregation is done per investor per Fund, unlike Company where aggregation is done per investor only
                           investment.funding_round_id
                         end

      ai = AggregateInvestment.where(investor_id: investment.investor_id,
                                     entity_id: investment.entity_id, funding_round_id:).first

      investment.aggregate_investment = ai.presence ||
                                        AggregateInvestment.create!(investor_id: investment.investor_id,
                                                                    entity_id: investment.entity_id,
                                                                    audit_comment: context.audit_comment,
                                                                    funding_round_id:)

      create_audit_trail(investment)
    end
  end

  def create_audit_trail(investment)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :create_aggregate_investment, owner: "Investment", quantity: investment.quantity, operation: :modify, ref: investment.aggregate_investment, entity_id: investment.entity_id, completed: true, parent_id: context.parent_id)
  end
end
