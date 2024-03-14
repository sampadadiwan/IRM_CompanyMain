class ApproveExcercise < OptionAction
  step :approve_excercise
  step :setup_holding_for_excercise
  step :update_existing_holding_post_excercise
  step :notify_excercise_approval
  left :handle_error

  def approve_excercise(ctx, excercise:, **)
    excercise.update(approved: true, approved_on: Time.zone.today, audit_comment: "#{ctx[:audit_comment]} : Excercise approved")
  end

  def setup_holding_for_excercise(_ctx, excercise:, **)
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

    CreateHolding.wtf?(holding:).success? &&
      ApproveHolding.wtf?(holding:).success? &&
      (excercise.cashless? ? CancelHolding.wtf?(holding: excercise.holding, all_or_unvested: "custom", shares_to_sell: excercise.shares_to_sell).success? : true)
  end

  def update_existing_holding_post_excercise(_ctx, excercise:, **)
    holding = excercise.holding.reload
    holding.save
  end

  def notify_excercise_approval(_ctx, excercise:, **)
    excercise.notify_approval
    true
  end

end
