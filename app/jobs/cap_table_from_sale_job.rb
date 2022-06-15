class CapTableFromSaleJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id)
    secondary_sale = SecondarySale.find(secondary_sale_id)
    Chewy.strategy(:sidekiq) do
      # Ensure all the holdings which are allocated in offers are marked as sold
      update_sold_holdings(secondary_sale)
      # Ensure that the interests are converted to investments
      create_investments(secondary_sale)
    end
  end

  def update_sold_holdings(secondary_sale)
    # Only consider approved and verified offers
    offers = secondary_sale.offers.approved.verified
    Rails.logger.debug { "offers = #{offers.count}" }
    offers.each do |offer|
      holding = offer.holding
      holding.sold_quantity = offer.allocation_quantity
      holding.save
    end
  end

  def create_investors(interest)
    # Create investors for the interests which are short_listed
    investor = Investor.where(investor_entity_id: interest.interest_entity_id,
                              investee_entity_id: interest.offer_entity_id).first

    if investor.nil?
      investor = Investor.create(investor_entity_id: interest.interest_entity_id,
                                 investee_entity_id: interest.offer_entity_id,
                                 investor_name: interest.interest_entity.name,
                                 category: "Co-Investor")

      # Create investor access for the investor
      InvestorAccess.create(investor:, user: interest.user,
                            first_name: interest.user.first_name, last_name: interest.user.last_name,
                            email: interest.user.email, approved: false,
                            entity_id: investor.investee_entity_id)
    end

    investor
  end

  def create_investments(secondary_sale)
    interests = secondary_sale.interests.short_listed
    Rails.logger.debug { "interests = #{interests.count}" }
    interests.each do |interest|
      # Create investor for the interest
      investor = create_investors(interest)

      offers = interest.offers.approved.verified.includes(:holding)
      equity_quantity    = offers.where("holdings.investment_instrument=?", "Equity").sum(:allocation_quantity)
      preferred_quantity = offers.where("holdings.investment_instrument=?", "Preferred").sum(:allocation_quantity)
      Rails.logger.debug { "offers = #{offers.count} equity_quantity = #{equity_quantity} preferred_quantity = #{preferred_quantity}" }

      if equity_quantity.positive?
        equity_investment = build_investment(secondary_sale, investor, "Equity", equity_quantity)
        SaveInvestment.call(investment: equity_investment, audit_comment: "Created from Interest #{interest.id}")
      end

      if preferred_quantity.positive?
        pref_investment = build_investment(secondary_sale, investor, "Preferred", preferred_quantity)
        SaveInvestment.call(investment: pref_investment, audit_comment: "Created from Interest #{interest.id}")
      end
    end
  end

  def build_investment(secondary_sale, investor, instrument, quantity)
    funding_round = FundingRound.create!(name: secondary_sale.name,
                                         currency: secondary_sale.entity.currency,
                                         entity_id: secondary_sale.entity_id,
                                         status: "Open")

    Investment.new(investment_instrument: instrument,
                   category: investor.category,
                   investee_entity_id: investor.investee_entity_id,
                   investor_id: investor.id, employee_holdings: false,
                   quantity:,
                   price_cents: secondary_sale.final_price * 100,
                   currency: secondary_sale.entity.currency,
                   funding_round:,
                   notes: "Investment from secondary sale #{secondary_sale.id} purchase")
  end
end
