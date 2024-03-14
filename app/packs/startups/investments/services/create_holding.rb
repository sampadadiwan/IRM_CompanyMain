class CreateHolding < HoldingAction
  step :update_holding_value
  step :new_holding
  left :handle_error

  def update_holding_value(_ctx, holding:, **)
    if holding.option_pool
      holding.funding_round_id = holding.option_pool.funding_round_id
      holding.price_cents = holding.option_pool.excercise_price_cents
    end
    holding.quantity = holding.orig_grant_quantity
    holding.value_cents = holding.quantity * holding.price_cents
    holding
  end

  def new_holding(ctx, holding:, **)
    holding.audit_comment = "#{ctx[:audit_comment]} : New Holding"
    holding.save
  end
end
