class UpdateHoldingValue
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateHoldingValue called"
    if context.holding.present?
      holding = context.holding
      update_value(holding)
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  def update_value(holding)
    if holding.option_pool
      holding.funding_round_id = holding.option_pool.funding_round_id
      holding.price_cents = holding.option_pool.excercise_price_cents
    end
    holding.quantity = holding.orig_grant_quantity
    holding.value_cents = holding.quantity * holding.price_cents
    holding
  end
end
