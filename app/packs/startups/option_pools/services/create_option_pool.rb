class CreateOptionPool < OptionAction
  step :setup_funding_round_for_pool
  step :create_pool
  left :handle_error

  def setup_funding_round_for_pool(ctx, option_pool:, **)
    funding_round = FundingRound.create(
      name: option_pool.name,
      currency: option_pool.entity.currency,
      entity_id: option_pool.entity_id,
      status: "Open",
      audit_comment: "#{ctx[:audit_comment]} : Create Funding Round"
    )
    option_pool.funding_round = funding_round

    funding_round.valid?
  end

  def create_pool(_ctx, option_pool:, **)
    option_pool.save
  end

end
