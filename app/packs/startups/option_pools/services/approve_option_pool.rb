class ApproveOptionPool < OptionAction
  step :approve_option_pool
  step :setup_trust_holdings
  left :handle_error

  def approve_option_pool(ctx, option_pool:, **)
    option_pool.update(approved: true, audit_comment: "#{ctx[:audit_comment]} :  Approve Pool")
  end

  def setup_trust_holdings(ctx, option_pool:, **)
    Rails.logger.debug "Option pool has been approved. Setting up trust holdings"
    trust_investor = option_pool.entity.trust_investor

    investment = Investment.where(funding_round_id: option_pool.funding_round_id, investor_id: trust_investor.id, investment_instrument: "Options").first

    if investment.present?
      Rails.logger.debug "Updating Investment for Trust for Option Pool"
      investment.quantity = option_pool.number_of_options

    else
      Rails.logger.debug "Creating Investment for Trust for Option Pool"
      investment = Investment.new(entity_id: option_pool.entity_id,
                                  category: "Trust",
                                  investment_date: Time.zone.today,
                                  quantity: option_pool.number_of_options,
                                  price_cents: option_pool.excercise_price_cents,
                                  investment_instrument: "Options", investor_id: trust_investor.id,
                                  funding_round_id: option_pool.funding_round_id)

    end

    SaveInvestment.call(investment:, audit_comment: "#{ctx[:audit_comment]} : Investment setup for Trust").success?
  end
end
