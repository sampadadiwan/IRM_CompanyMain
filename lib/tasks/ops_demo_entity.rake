# Creates a complete demo fund-manager entity for trying AI ops agents (Paperclip) against CapHive's MCP
# server: "Northwind Capital Partners" (INR) with a closed-ended fund (8 LPs, 4 portfolio companies,
# 3 capital calls, 1 distribution), an open-ended fund (built by evergreen:seed_demo_fund's
# EvergreenDemoFund), an ops user, a read-only MCP service user and an OAuth token for it.
#
# The closed fund carries deliberate ops problems (P1–P8: overdue and pending remittances, an unverified
# receipt, an LP never notified, an onboarding gap, an unpaid distribution, a stale valuation, a stuck
# e-sign) so an agent sweeping the entity has real work to find. Call 1 is clean on purpose — a correct
# sweep raises nothing for it. The task prints the planted problems with their folio ids at the end.
#
#   bin/rails ops_demo:seed                                   # dry run: print the plan
#   bin/rails ops_demo:seed EXECUTE=1                         # build it
#   bin/rails ops_demo:seed ENTITY_NAME="Northwind 2" EXECUTE=1
#
# Development / staging only. Logic: lib/tasks/support/ops_demo_entity.rb. Paperclip setup that uses it:
# docs/ops/paperclip/README.md
require_relative "support/evergreen_demo_portfolio"
require_relative "support/evergreen_demo_fund"
require_relative "support/ops_demo_entity"

namespace :ops_demo do
  desc "Create a demo INR entity (closed + open-ended fund, planted ops problems, MCP bot token) for Paperclip; dry run unless EXECUTE=1"
  task seed: :environment do
    raise "Demo data — never in production" if Rails.env.production?

    # Never reload code mid-run: inline jobs pass through the reloader (see evergreen_demo_fund.rake)
    Rails.application.reloader.check = -> { false }

    Chewy.strategy(:atomic) do
      OpsDemoEntity.new(name: ENV.fetch("ENTITY_NAME", OpsDemoEntity::DEFAULT_NAME), execute: ENV["EXECUTE"] == "1").run
    end
  end
end
