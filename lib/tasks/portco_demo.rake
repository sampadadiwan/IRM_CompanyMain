# Seeds N demo portfolio companies with 12 quarters of KPIs, 6 half-yearly per-share valuations and generated
# documents: an IC note and annual summaries on each company, and a Quarterly Update, Board Meeting Notes and
# Investor Presentation on every quarterly KPI report. With FUND_ID it also records the fund's buy of each company
# and 4 LP commitments, each with a verified KYC. Ends with a note (links + descriptions) to send to the business.
# Development / staging data only.
#
#   bin/rails portco_demo:seed ENTITY_ID=157 N=5                         # dry run: print the plan
#   bin/rails portco_demo:seed ENTITY_ID=157 N=5 EXECUTE=1               # create it
#   bin/rails portco_demo:seed ENTITY_ID=157 N=5 FUND_ID=343 EXECUTE=1   # also record the fund's buy of each company
#
# With a USD FUND_ID the task also creates the records the two US sample documents describe: Harborview's
# US$1M commitment carrying US_Growth_Fund_LP_Side_Letter.docx (tagged "Side Letter"), and the fund's purchase
# of 250,000 Aster Labs shares at $2.50 carrying US_Stock_Purchase_Agreement_CP_CS.docx (tagged "SPA"); a blank
# CP/CS extraction agent investment_doc_tag is set to "SPA" so the agent finds it.
# Note links use BASE_URL (default http://localhost:3000).
# Idempotent: every record is looked up before it is created. Helpers: lib/tasks/support/portco_demo.rb
require_relative "support/portco_demo"

namespace :portco_demo do
  desc "Seed N demo portfolio companies with KPIs, valuations, documents and (with FUND_ID) LP commitments + KYCs (ENTITY_ID=, N=, FUND_ID=; dry run unless EXECUTE=1)"
  task seed: :environment do
    raise "Demo data - never in production" if Rails.env.production?

    # Inputs: the entity is required; N defaults to 5; the fund is optional and must belong to the entity
    entity = Entity.find(ENV.fetch("ENTITY_ID") { abort "ENTITY_ID is required" })
    count = Integer(ENV.fetch("N", "5"))
    abort "N must be at least 1" unless count.positive?
    fund = ENV["FUND_ID"].present? ? entity.funds.find(ENV["FUND_ID"]) : nil
    user = User.where(entity_id: entity.id).order(:id).first
    abort "Entity #{entity.id} has no users - KPI reports and documents need one" unless user

    # Figures follow the fund's currency, else the entity's; the US sample documents need a USD fund
    units = PortcoDemo::Units.new(fund&.currency.presence || entity.currency.presence || "INR")
    us_docs = fund.present? && units.currency == "USD"
    execute = ENV["EXECUTE"] == "1"
    puts(execute ? "EXECUTE: seeding" : "DRY RUN - set EXECUTE=1 to create")
    puts "Entity #{entity.id} (#{entity.name}), #{count} companies in #{units.currency}" + (fund ? ", fund #{fund.id} (#{fund.name})" : "")
    puts "  US side letter and SPA skipped - they need a USD FUND_ID" if fund && !us_docs
    puts "  Commitments and KYCs skipped - they need a FUND_ID" unless fund

    seeder = PortcoDemo::Seeder.new(entity:, user:, fund:, execute:)
    count.times do |i|
      # Profiles in order; past the last one, start again with a numbered name ("... II")
      company = PortcoDemo::Company.new(profile_index: i % PortcoDemo::PROFILES.size, round: i / PortcoDemo::PROFILES.size,
                                        units:, today: Time.zone.today, us_docs:)
      seeder.seed_company(company)
    end
    # The fund's LPs (commitment + verified KYC each), commitments starting with the KPI history
    seeder.seed_commitments(units:, start_date: PortcoDemo.quarter_ends(Time.zone.today).first) if fund
    seeder.configure_cp_cs_agent if us_docs
    # The note for the business, only once the records exist
    seeder.print_note(units) if execute
  end
end
