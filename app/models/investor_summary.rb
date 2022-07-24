class InvestorSummary
  def initialize(params, user)
    @params = params
    @user = user

    entity_id = params[:entity_id]
    @entity = Entity.find(entity_id)

    # This is an investor - so find the investor
    @investor = Investor.for(@user, @entity).first
  end

  def estimated_profits(price_growth)
    profits = Money.new(0, @entity.currency)

    @holdings ||= @investor.holdings.eq_and_pref.where(entity_id: @entity.id).includes(funding_round: :entity, entity: :valuations)

    per_share_value = @entity.valuations.last.per_share_value

    @holdings.each do |holding|
      profits += (per_share_value * price_growth * holding.quantity) - holding.value
    end

    Rails.logger.debug { "estimated_profits = #{profits}" }

    profits
  end

  def investor_summary
    last_valuation = @entity.valuations.last&.per_share_value
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    if last_valuation
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value =
        from_last_valuation(last_valuation)
    else
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value =
        no_valuation
    end

    [price_growth, tax_rate, estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value]
  end

  def from_last_valuation(last_valuation)
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    estimated_profit = estimated_profits(price_growth)
    estimated_taxes = estimated_profit * tax_rate / 100
    holdings = @investor.holdings.eq_and_pref.where(entity_id: @entity.id)
    total_value_cents = holdings.sum(:value_cents)

    holding_value = Money.new(total_value_cents, @entity.currency)

    cost_neutral_sale = (estimated_taxes + holding_value) / (last_valuation * price_growth)
    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value]
  end

  def no_valuation
    estimated_taxes = Money.new(0, @entity.currency)
    estimated_profit = Money.new(0, @entity.currency)
    cost_neutral_sale = 0
    last_valuation = Money.new(0, @entity.currency)
    holding_value = Money.new(0, @entity.currency)

    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value]
  end

  def projected_profits
    # This sets which holdings the employee is seeing
    [2, 3, 4, 5, 6, 7, 8, 9, 10].map do |price_growth|
      [price_growth, estimated_profits(price_growth).cents / 100]
    end
  end
end
