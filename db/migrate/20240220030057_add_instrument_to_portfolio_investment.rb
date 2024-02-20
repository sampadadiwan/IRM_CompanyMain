class AddInstrumentToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    # Ensure no invalid portfolios
    PortfolioInvestment.where(category: nil).update_all(category: "Unlisted")
    PortfolioInvestment.where(category: "").update_all(category: "Unlisted")
    PortfolioInvestment.where(sub_category: nil).update_all(sub_category: "Equity")
    PortfolioInvestment.where(sub_category: "").update_all(sub_category: "Equity")
    PortfolioInvestment.where(sector: nil).update_all(sector: "N/A")
    PortfolioInvestment.where(sector: "").update_all(sector: "N/A")
    PortfolioInvestment.where("amount_cents < 0").update_all("amount_cents = amount_cents * -1")
    Valuation.where(owner_type: "Investor", category: nil).update_all(category: "Unlisted")
    Valuation.where(owner_type: "Investor", sub_category: nil).update_all(category: "Equity")
    # Setup fake instruments    
    PortfolioInvestment.all.each do |pi|
      pc = pi.portfolio_company
      if pc.investment_instruments.where(category: pi.category, sub_category: pi.sub_category).empty?
        pc.investment_instruments.create!(name: (0...8).map { (65 + rand(26)).chr }.join, category: pi.category, sub_category: pi.sub_category, entity_id: pc.entity_id)
      end
    end

    # Add the reference
    add_reference :portfolio_investments, :investment_instrument, null: true, foreign_key: true
    add_reference :aggregate_portfolio_investments, :investment_instrument, null: true, foreign_key: true
    add_reference :scenario_investments, :investment_instrument, null: true, foreign_key: true
    add_reference :valuations, :investment_instrument, null: true, foreign_key: true

    
    # # Update the reference
    # PortfolioInvestment.all.each do |pi|
    #   pi.update(investment_instrument: pi.portfolio_company.investment_instruments.find_by(category: pi.category, sub_category: pi.sub_category))
    # end

    # AggregatePortfolioInvestment.all.each do |api|
    #   category, sub_category = api.investment_type.split(" : ")
    #   api.update(investment_instrument: api.portfolio_company.investment_instruments.find_by(category:, sub_category:))
    # end

    # ScenarioInvestment.all.each do |si|
    #   si.update(investment_instrument: si.portfolio_company.investment_instruments.find_by(category: si.category, sub_category: si.sub_category))
    # end

    # Valuation.all.each do |si|
    #   si.update(investment_instrument: si.owner.investment_instruments.find_by(category: si.category, sub_category: si.sub_category)) if si.owner_type == "Investor"
    # end
  end
end
