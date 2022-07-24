module InvestmentConcern
  extend ActiveSupport::Concern

  def new_multi_investments(params, investment_params)
    investments = []

    params[:investment][:investment_instrument].each_with_index do |instrument, idx|
      quantity, price, liquidation_preference, spv, investment_date = parse_params(params, idx)

      next unless instrument.present? && quantity.present? && price.present?

      @investment = Investment.new(investment_params)
      @investment.entity_id = current_user.entity_id
      @investment.currency = current_user.entity.currency
      @investment.investment_instrument = instrument
      @investment.quantity = quantity
      @investment.price_cents = price.to_f * 100
      @investment.spv = spv
      @investment.liquidation_preference = liquidation_preference
      @investment.investment_date = investment_date

      authorize @investment
      investments << @investment
    end

    investments
  end

  def parse_params(params, idx)
    quantity = params[:investment][:quantity][idx]
    price = params[:investment][:price][idx]
    liquidation_preference = params[:investment][:liquidation_preference][idx]
    spv = params[:investment][:spv][idx]
    investment_date = params[:investment][:investment_date][idx]
    [quantity, price, liquidation_preference, spv, investment_date]
  end
end
