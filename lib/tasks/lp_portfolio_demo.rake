# Seeds a self-contained demo of the LP folio portfolio & company dashboard feature (its own fund manager, fund,
# two LPs, holdings, folio allocation entries, KPIs, a founder video and LP layouts) and prints the URLs to
# review every screen. Development / staging only.
#
#   bin/rails lp_portfolio:seed_demo                                  # dry run: print the plan
#   bin/rails lp_portfolio:seed_demo EXECUTE=1                        # build it and print the review URLs
#   bin/rails lp_portfolio:seed_demo EXECUTE=1 HOST=http://localhost:3000
#
# Re-running reuses what exists and prints the URLs again. Logic: lib/tasks/support/lp_portfolio_demo.rb
# openspec/changes/lp-folio-portfolio-dashboard
require_relative "support/lp_portfolio_demo"

namespace :lp_portfolio do
  desc "Seed a demo of the LP folio portfolio & company dashboard and print review URLs (dry run unless EXECUTE=1; not in production)"
  task seed_demo: :environment do
    raise "Demo data — never in production" if Rails.env.production?

    # Never reload code mid-run (inline jobs pass through the reloader), as the other demo tasks do
    Rails.application.reloader.check = -> { false }
    # HOST may be set without a scheme (e.g. localhost:3001) in a developer's shell
    host = ENV.fetch("HOST", "localhost:3000")
    host = "http://#{host}" unless host.start_with?("http")
    # Search indexes update atomically outside a request, as in the evergreen demo task
    Chewy.strategy(:atomic) { LpPortfolioDemo.new(execute: ENV["EXECUTE"] == "1", host:).run }
  end
end
