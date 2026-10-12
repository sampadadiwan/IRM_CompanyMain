# Gives a test evergreen fund a real portfolio, so its NAV is drafted from holdings × valuations
# (NavInputs#investments_fmv_cents) instead of only uploaded NAVs. Development / staging data only.
#
#   bin/rails evergreen:seed_demo_portfolio FUND_ID=343             # dry run: print the plan
#   bin/rails evergreen:seed_demo_portfolio FUND_ID=343 EXECUTE=1   # create it
#
# Creates three demo portfolio companies of the fund's entity (new ones, so other funds' valuations are
# untouched), one equity instrument each, a buy per company through PortfolioInvestmentCreate (which
# records the cost valuation), later valuations, and a fund-level "Cash In Hand" balance.
# Idempotent: a company the fund already holds is skipped. Feature: features/fund/evergreen/nav_from_portfolio.feature
require_relative "support/evergreen_demo_portfolio"

namespace :evergreen do
  demo_holdings = [
    # name, shares, bought on, cost (₹), valuations { date => ₹ a share }
    ["Acme Robotics Pvt Ltd", 60_000, "2025-09-01", 60_000_000, { "2026-06-30" => 1_150, "2026-09-30" => 1_220 }],
    ["Beta Foods Ltd", 25_000, "2025-09-01", 50_000_000, { "2026-09-30" => 2_300 }],
    ["Gamma Fintech Pvt Ltd", 40_000, "2025-09-01", 60_000_000, { "2026-03-31" => 1_600, "2026-09-30" => 1_750 }]
  ].freeze
  demo_cash = { date: "2026-09-30", amount: 12_000_000 }.freeze

  desc "Seed a demo portfolio for a test evergreen fund (FUND_ID=, dry run unless EXECUTE=1; not in production)"
  task seed_demo_portfolio: :environment do
    raise "Demo data — never in production" if Rails.env.production?

    fund = Fund.find(ENV.fetch("FUND_ID"))
    raise "Fund #{fund.id} is not evergreen" unless fund.evergreen?

    execute = ENV["EXECUTE"] == "1"
    puts(execute ? "EXECUTE: seeding #{fund.name} (#{fund.id})" : "DRY RUN for #{fund.name} (#{fund.id}) — set EXECUTE=1 to create")
    entity = fund.entity
    user = User.where(entity_id: entity.id).order(:id).first

    ActiveRecord::Base.transaction do
      demo_holdings.each do |name, shares, bought_on, cost, valuations|
        pc = entity.investors.portfolio_companies.find_by(investor_name: name)
        if pc && fund.portfolio_investments.exists?(portfolio_company_id: pc.id)
          puts "  #{name}: already held — skipped"
          next
        end
        puts "  #{name}: buy #{shares} shares on #{bought_on} for ₹#{cost}; valuations #{valuations.map { |d, v| "#{d} ₹#{v}" }.join(', ')}"
        next unless execute

        # Company (new if missing), instrument and the buy, through the shared demo helpers
        pc, instrument = EvergreenDemoPortfolio.buy(fund, name:, shares:, bought_on: Date.parse(bought_on), cost_cents: cost * 100,
                                                          notes: "Demo holding (evergreen:seed_demo_portfolio)")
        valuations.each do |date, per_share|
          EvergreenDemoPortfolio.value(fund, pc, instrument, date: Date.parse(date), per_share_cents: per_share * 100, shares:)
        end
      end

      # The fund's cash: the latest "Cash In Hand" fund entry on or before a NAV date is the cash line
      cash_name = fund.evergreen_fund_setting.cash_entry_name
      if fund.fund_account_entries.exists?(name: cash_name, reporting_date: ..Date.parse(demo_cash[:date]))
        puts "  #{cash_name}: a balance already exists — skipped"
      else
        puts "  #{cash_name}: ₹#{demo_cash[:amount]} on #{demo_cash[:date]}"
        if execute
          AccountEntry.create!(entity:, fund:, name: cash_name, entry_type: cash_name, reporting_date: Date.parse(demo_cash[:date]),
                               amount_cents: demo_cash[:amount] * 100, notes: "Demo cash (evergreen:seed_demo_portfolio)")
        end
      end
    end
    puts "Done. Draft a NAV on the fund's NAV tab to see the holdings in it." if execute && user
  end
end
