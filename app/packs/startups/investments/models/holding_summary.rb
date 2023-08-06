class HoldingSummary
  def initialize(params, user)
    @params = params
    @user = user
    # This is an employee - so find his parent company

    entity_id = params[:entity_id].presence || user.employee_parent_entity&.id
    @entity = Entity.find(entity_id)
  end

  def estimated_profits(price_growth)
    profits = Money.new(0, @entity.currency)

    @holdings ||= @user.holdings.options.where(entity_id: @entity.id).includes(option_pool: :entity, entity: :valuations)

    @holdings.each do |holding|
      per_share_value = holding.entity.valuations.last.per_share_value
      quantity = if @params[:quantity].present?
                   @params[:quantity].to_i
                 else
                   @params[:all_or_vested] == "Vested" ? holding.vested_quantity : holding.quantity
                 end
      profits += ((per_share_value * price_growth) - holding.option_pool.excercise_price) * quantity
    end

    profits
  end

  def employee_summary
    last_valuation = @entity.valuations.last&.per_share_value
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    if last_valuation
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, esop_value =
        from_last_valuation(last_valuation)
    else
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, esop_value =
        no_valuation
    end

    [price_growth, tax_rate, estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, esop_value]
  end

  def from_last_valuation(last_valuation)
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    estimated_profit = estimated_profits(price_growth)
    estimated_taxes = estimated_profit * tax_rate / 100
    options = @user.holdings.options.where(entity_id: @entity.id)
    total_value_cents = if @params[:all_or_vested] == "Vested"
                          options.inject(0) { |sum, h| sum + (h.vested_quantity * h.price_cents) }
                        else
                          options.sum(:value_cents)
                        end
    esop_value = Money.new(total_value_cents, @entity.currency)

    cost_neutral_sale = (estimated_taxes + esop_value) / (last_valuation * price_growth)
    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, esop_value]
  end

  def no_valuation
    estimated_taxes = Money.new(0, @entity.currency)
    estimated_profit = Money.new(0, @entity.currency)
    cost_neutral_sale = 0
    last_valuation = Money.new(0, @entity.currency)
    esop_value = Money.new(0, @entity.currency)

    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, esop_value]
  end

  def projected_profits
    # This sets which holdings the employee is seeing
    [2, 3, 4, 5, 6, 7, 8, 9, 10].map do |price_growth|
      [price_growth, estimated_profits(price_growth).cents / 100]
    end
  end
end
