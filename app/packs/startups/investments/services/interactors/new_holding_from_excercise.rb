class NewHoldingFromExcercise
  include Interactor

  def call
    Rails.logger.debug "Interactor: NewHoldingFromExcercise called"

    if context.excercise.present?
      create_holding(context.excercise)
    else
      Rails.logger.debug "No Excercise specified"
      context.fail!(message: "No Excercise specified")
    end
  end

  def create_holding(excercise)
    # Generate the equity holding to update the cap table
    quantity = excercise.cashless? ? excercise.shares_to_allot : excercise.quantity
    holding = Holding.new(user_id: excercise.user_id, entity_id: excercise.entity_id,
                          orig_grant_quantity: quantity,
                          grant_date: Time.zone.today,
                          price_cents: excercise.price_cents,
                          investment_instrument: "Equity", investor_id: excercise.holding.investor_id,
                          holding_type: excercise.holding.holding_type,
                          funding_round_id: excercise.option_pool.funding_round_id,
                          employee_id: excercise.holding.employee_id, created_from_excercise_id: excercise.id, approved: true)

    CreateHolding.call(holding:)
    ApproveHolding.call(holding:)
    CancelHolding.call(holding: excercise.holding, all_or_unvested: "custom", shares_to_sell: excercise.shares_to_sell) if excercise.cashless?
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :create_holding, owner: "Holding", quantity: holding.quantity, operation: :create_record, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.excercise.created_holding)
  end
end
