# Shared portfolio helpers for the evergreen demo rake tasks (lib/tasks/evergreen_demo_portfolio.rake,
# lib/tasks/evergreen_demo_fund.rake): a portfolio company of the fund's entity, one equity instrument,
# a buy through PortfolioInvestmentCreate (which records the cost valuation) and later valuations.
# Development / staging data only.
module EvergreenDemoPortfolio
  # The entity's portfolio company with this name, created (with its own investor entity, as the
  # portfolio company form creates it) when missing
  def self.portfolio_company(entity, name)
    pc = entity.investors.portfolio_companies.find_by(investor_name: name)
    return pc if pc

    # Short and stable: the investor-entity email lock name (MySQL GET_LOCK) is capped at 64 characters
    email = "demo+#{Digest::MD5.hexdigest(name).first(10)}@example.com"
    # Name + email is unique (Entity validates name scoped to primary_email), so a company another demo
    # entity already created with this stable email is reused rather than re-created

    investor_entity = Entity.find_by(primary_email: email) || Entity.create!(name:, entity_type: "Company", primary_email: email)
    entity.investors.create!(investor_name: name, investor_entity:, category: "Portfolio Company", primary_email: email)
  end

  # One equity instrument per company, in the fund's currency. Valuations are keyed by company +
  # instrument, so a caller wanting its own price history passes its own instrument name.
  def self.instrument(fund, pc, sector: "Tech", name: nil)
    InvestmentInstrument.find_or_create_by!(entity: fund.entity, portfolio_company: pc, name: name || "#{pc.investor_name} Equity") do |i|
      i.category = "Unlisted"
      i.sub_category = "Equity"
      i.sector = sector
      i.currency = fund.currency
    end
  end

  # Buy shares through the app's own service. Returns [portfolio company, instrument].
  def self.buy(fund, name:, shares:, bought_on:, cost_cents:, notes:, sector: "Tech", instrument_name: nil)
    pc = portfolio_company(fund.entity, name)
    instrument = instrument(fund, pc, sector:, name: instrument_name)
    pi = PortfolioInvestment.new(entity: fund.entity, fund:, portfolio_company: pc, investment_instrument: instrument, investment_date: bought_on,
                                 quantity: shares, ex_expenses_base_amount_cents: cost_cents, category: "Unlisted", sub_category: "Equity",
                                 sector:, notes:)
    result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
    raise "#{name}: #{pi.errors.full_messages.to_sentence.presence || result[:errors]}" unless result.success?

    [pc, instrument]
  end

  # A valuation of the company's instrument on a date. Valuations belong to the company + instrument,
  # not the fund, so an existing one for the date is kept (idempotent re-runs).
  def self.value(fund, pc, instrument, date:, per_share_cents:, shares:)
    Valuation.find_or_create_by!(entity: fund.entity, owner: pc, investment_instrument: instrument, valuation_date: date) do |v|
      v.category = "Unlisted"
      v.sub_category = "Equity"
      v.per_share_value_cents = per_share_cents
      v.valuation_cents = per_share_cents * shares
    end
  end
end
