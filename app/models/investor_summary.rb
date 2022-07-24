class InvestorSummary
  def initialize(params, user)
    @params = params
    @user = user

    entity_id = params[:entity_id]
    @entity = Entity.find(entity_id)

    # This is an investor - so find the investor
    @investor = Investor.for(@user, @entity).first
  end

  def investments
    investor_investments ||= @investor.investments.equity_or_pref.where(entity_id: @entity.id)
                                      .includes(:funding_round, entity: :valuations)

    investor_investments
  end

  def estimated_profits(price_growth)
    exit_value = 0
    total_holding_value = Money.new(0, @entity.currency)
    per_share_value = @entity.per_share_value

    investments.each do |inv|
      exit_value += (per_share_value * price_growth * inv.quantity)
      total_holding_value += inv.amount
    end

    profits = exit_value - total_holding_value
    Rails.logger.debug { "estimated_profits : exit_value = #{exit_value}" }

    [exit_value, total_holding_value, profits]
  end

  def investor_summary
    last_valuation = @entity.valuations.last&.per_share_value
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    if last_valuation
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value, xirr =
        from_last_valuation(last_valuation)
    else
      estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value, xirr =
        no_valuation
    end

    [price_growth, tax_rate, estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value, xirr]
  end

  def from_last_valuation(last_valuation)
    # Get the price growth from the UI
    price_growth = @params[:price_growth].present? ? @params[:price_growth].to_f : 3
    # Get the tax rate from the UI
    tax_rate = @params[:tax_rate] ? @params[:tax_rate].to_f : 30

    exit_value, total_value_cents, estimated_profit = estimated_profits(price_growth)
    estimated_taxes = estimated_profit * tax_rate / 100

    holding_value = Money.new(total_value_cents, @entity.currency)

    cost_neutral_sale = (estimated_taxes + holding_value) / (last_valuation * price_growth)
    xirr = compute_xirr(exit_value)

    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value, xirr]
  end

  def no_valuation
    estimated_taxes = Money.new(0, @entity.currency)
    estimated_profit = Money.new(0, @entity.currency)
    cost_neutral_sale = 0
    last_valuation = Money.new(0, @entity.currency)
    holding_value = Money.new(0, @entity.currency)
    xirr = 0

    [estimated_taxes, estimated_profit, cost_neutral_sale, last_valuation, holding_value, xirr]
  end

  def projected_profits
    # This sets which investments the employee is seeing
    [2, 3, 4, 5, 6, 7, 8, 9, 10].map do |price_growth|
      _exit_value, _total_value_cents, estimated_profit = estimated_profits(price_growth)
      [price_growth, estimated_profit.cents / 100]
    end
  end

  def compute_xirr(exit_value)
    Rails.logger.debug { "compute_xirr exit_value: #{exit_value}" }
    cf = Xirr::Cashflow.new

    investments.each do |inv|
      cf << Xirr::Transaction.new(-1 * inv.amount, date: inv.investment_date)
    end

    cf << Xirr::Transaction.new(exit_value, date: Time.zone.today)

    Rails.logger.debug { "compute_xirr cf: #{cf}" }
    Rails.logger.debug { "compute_xirr irr: #{cf.xirr}" }
    cf.xirr * 100
  end

  def self.test_xirr
    cf = Xirr::Cashflow.new
    cf << Xirr::Transaction.new(-50, date: '2020-1-1'.to_date)
    cf << Xirr::Transaction.new(-10, date: '2020-9-1'.to_date)
    cf << Xirr::Transaction.new(-12, date: '2021-1-1'.to_date)
    cf << Xirr::Transaction.new(-13.5, date: '2021-6-1'.to_date)
    cf << Xirr::Transaction.new(142.2, date: '2022-12-31'.to_date)
    cf.xirr
  end
end
