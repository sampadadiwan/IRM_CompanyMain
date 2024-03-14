class SaveInvestment < Trailblazer::Operation
  step :create_aggregate_investment
  step :save_investment
  step :update_investor_holdings
  step :update_investor_category
  step :recompute_investment_percentages
  left :handle_error

  def handle_error(ctx, investment:, **)
    Rails.logger.error investment.errors.full_messages.join(', ').to_s
    ctx[:errors] = investment.errors.full_messages.join(", ")
  end

  def create_aggregate_investment(ctx, investment:, **)
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
                                        AggregateInvestment.create(investor_id: investment.investor_id, funding_round_id:,
                                                                   entity_id: investment.entity_id, audit_comment: ctx[:audit_comment])

      return investment.aggregate_investment.valid?
    end
    true
  end

  def save_investment(_ctx, investment:, **)
    investment.save
  end

  def update_investor_holdings(ctx, investment:, **)
    # For Investors (Not Employees or Founders), we want to create a holding
    # corresponding to this investment.
    # There will be only one such Holding per investment
    # Rails.logger.debug { "update_investor_holdings: investment.investor = #{investment.investor.investor_name}" }
    if !investment.investor.is_holdings_entity &&
       Investment::EQUITY_LIKE.include?(investment.investment_instrument)

      holding = investment.holdings.first
      if holding
        # Since there is only 1 holding per Investor Investment
        # Just assign the quantity and price
        holding.update(orig_grant_quantity: investment.quantity,
                       investment_instrument: investment.investment_instrument,
                       price: investment.price,
                       audit_comment: "Updated by UpdateInvestorHoldings")
      else
        holding = Holding.new(entity: investment.entity, investment_id: investment.id,
                              investor_id: investment.investor_id, funding_round_id: investment.funding_round_id,
                              option_pool: investment.funding_round.option_pool,
                              grant_date: investment.investment_date, holding_type: "Investor",
                              investment_instrument: investment.investment_instrument,
                              orig_grant_quantity: investment.quantity,
                              price_cents: investment.price_cents,
                              value_cents: investment.amount_cents, approved: true)

        audit_comment = "#{ctx[:audit_comment]} : Update Investor Holding"
        CreateHolding.wtf?(holding:, audit_comment:)
      end

    else
      # For Debt and other Non Equity - we dont need a holding
      Rails.logger.debug { "Not creating holdings for #{investment.to_json}" }
      true
    end
  end

  def update_investor_category(_ctx, investment:, **)
    # Update the investor category to the investment category
    investor = investment.investor
    investor.category = investment.category
    investor.save
  end

  def recompute_investment_percentages(_ctx, investment:, **)
    investment.entity.recompute_investment_percentages
  end
end
