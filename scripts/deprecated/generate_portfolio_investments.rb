require 'factory_bot_rails'

entity_id = 157
Chewy.strategy(:atomic) do
  # 1. Find or create a Fund for this entity
  fund = Fund.find_or_create_by!(entity_id: entity_id, name: "IRM Alpha Fund") do |f|
    f.currency = "USD"
    f.category = "PE"
  end
  puts "Using Fund: #{fund.name} (ID: #{fund.id})"

  # 2. Get all portfolio companies for this entity
  portcos = Investor.where(entity_id: entity_id, category: "Portfolio Company")
  puts "Found #{portcos.count} portfolio companies."

  portcos.each do |portco|
    puts "Creating portfolio investments for #{portco.investor_name}..."
    
    # 3. Create an Investment Instrument for this company
    # Some companies might already have one, but we'll try to find or create
    instrument = InvestmentInstrument.find_or_create_by!(
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      name: "Common Equity - #{portco.investor_name}"
    ) do |ii|
      ii.category = "Unlisted"
      ii.sub_category = "Equity"
      ii.sector = portco.sector || "SaaS"
      ii.currency = "USD"
    end

    # 3.5 Create AggregatePortfolioInvestment explicitly
    api_record = AggregatePortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      investment_instrument_id: instrument.id
    ) do |api|
      api.portfolio_company_name = portco.investor_name
      # The monetization might need these set to 0 explicitly if they're causing validation issues
      api.bought_amount_cents = 0
      api.sold_amount_cents = 0
      api.net_bought_amount_cents = 0
      api.fmv_cents = 0
      api.gain_cents = 0
      api.unrealized_gain_cents = 0
      api.avg_cost_cents = 0
      api.cost_of_remaining_cents = 0
      api.cost_of_sold_cents = 0
      api.portfolio_income_cents = 0
      api.ex_expenses_amount_cents = 0
      api.tracking_bought_amount_cents = 0
      api.tracking_sold_amount_cents = 0
      api.tracking_fmv_cents = 0
    end

    # 4. Create one or two PortfolioInvestments
    # Seed Round
    amount = 50000000 # $500k
    quantity = 10000
    
    PortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      investment_instrument_id: instrument.id,
      investment_date: 1.year.ago.to_date,
      aggregate_portfolio_investment_id: api_record.id # Link it here
    ) do |pi|
      pi.ex_expenses_base_amount_cents = amount
      pi.base_amount_cents = amount
      pi.ex_expenses_amount_cents = amount
      pi.amount_cents = amount
      pi.net_bought_amount_cents = amount
      pi.net_amount_cents = amount
      pi.quantity = quantity
      pi.sub_category = "Equity"
      pi.category = "Unlisted"
      pi.sector = instrument.sector
      pi.notes = "Seed round investment"
    end

    # Series A (for some)
    if [true, false].sample
      amount_a = 150000000 # $1.5M
      quantity_a = 5000
      
      PortfolioInvestment.find_or_create_by!(
        fund_id: fund.id,
        entity_id: entity_id,
        portfolio_company_id: portco.id,
        investment_instrument_id: instrument.id,
        investment_date: 6.months.ago.to_date,
        aggregate_portfolio_investment_id: api_record.id # Link it here
      ) do |pi|
        pi.ex_expenses_base_amount_cents = amount_a
        pi.base_amount_cents = amount_a
        pi.ex_expenses_amount_cents = amount_a
        pi.amount_cents = amount_a
        pi.net_bought_amount_cents = amount_a
        pi.net_amount_cents = amount_a
        pi.quantity = quantity_a
        pi.sub_category = "Equity"
        pi.category = "Unlisted"
        pi.sector = instrument.sector
        pi.notes = "Series A round investment"
      end
    end
  end
end

puts "Done generating portfolio investments!"
