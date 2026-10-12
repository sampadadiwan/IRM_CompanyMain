# Creates a complete demo open-ended (evergreen) fund for an existing entity: settings and two unit
# classes, investors with approved KYCs and folios, a portfolio with valuations, cash and fee ledger
# entries, approved NAVs, ~6 months of confirmed dealing dates (settled subscriptions, redemptions with
# an early-redemption fee, a gate on USD) and open orders on the next dates. Development / staging only.
#
#   bin/rails evergreen:seed_demo_fund ENTITY_ID=12                                # dry run, USD: print the plan
#   bin/rails evergreen:seed_demo_fund ENTITY_ID=12 CURR=INR EXECUTE=1             # create an INR fund
#   bin/rails evergreen:seed_demo_fund ENTITY_ID=12 PORTFOLIO=public EXECUTE=1     # INR, listed securities
#   bin/rails evergreen:seed_demo_fund ENTITY_ID=12 PORTFOLIO=hybrid EXECUTE=1     # INR, private + listed
#
# CURR is USD (default) or INR: it picks the fund currency, the settings preset (US tender-offer /
# Indian Cat III AIF), prices, minimums, investor and company names and amounts.
# PORTFOLIO picks what the fund holds:
#   private (default) — private companies valued monthly by hand; no market data
#   public            — NSE/BSE listed securities on daily Market prices plus one USD share, with every
#                       fund market data feature (FX sources, own rates, derivatives, corporate actions)
#   hybrid            — the private companies next to listed holdings, plus the derivatives and
#                       corporate actions
# public and hybrid are INR only and switch market data on for the new fund alone — other funds of
# the entity are not changed (rules in lib/tasks/support/market_data_demo.rb).
# Each run creates a new fund (the name carries the time); investors and portfolio companies are
# reused by name. The entity needs a user with the approver role. Logic: lib/tasks/support/evergreen_demo_fund.rb
# (public / hybrid: lib/tasks/support/evergreen_demo_market_fund.rb)
require_relative "support/evergreen_demo_portfolio"
require_relative "support/evergreen_demo_fund"
require_relative "support/market_data_demo"
require_relative "support/evergreen_demo_market_fund"

namespace :evergreen do
  desc "Create a complete demo open-ended fund (ENTITY_ID=, CURR=USD|INR, PORTFOLIO=private|public|hybrid, dry run unless EXECUTE=1; not in production)"
  task seed_demo_fund: :environment do
    raise "Demo data — never in production" if Rails.env.production?

    # Never reload code mid-run: inline jobs pass through the reloader, and an app file saved meanwhile
    # (development) would unload Fund etc. under the records this task holds (AssociationTypeMismatch)
    Rails.application.reloader.check = -> { false }

    entity = Entity.find(ENV.fetch("ENTITY_ID") { abort "ENTITY_ID is required" })
    currency = ENV.fetch("CURR", "USD").upcase
    portfolio = ENV.fetch("PORTFOLIO", "private").downcase
    execute = ENV["EXECUTE"] == "1"
    case portfolio
    when "private"
      EvergreenDemoFund.new(entity:, currency:, execute:).run
    when *EvergreenDemoMarketFund::PORTFOLIOS
      # Listed securities are priced in INR (NSE / BSE)
      abort "PORTFOLIO=#{portfolio} builds an INR fund — drop CURR or set CURR=INR" if ENV.key?("CURR") && currency != "INR"
      Chewy.strategy(:atomic) { EvergreenDemoMarketFund.new(entity:, execute:, portfolio:).run }
    else
      abort "PORTFOLIO must be private, public or hybrid"
    end
  end
end
