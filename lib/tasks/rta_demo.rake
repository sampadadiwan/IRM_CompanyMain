# frozen_string_literal: true

namespace :rta do
  desc "Ensure a fund's FundUnitSettings all have ISINs, generate an all-success and an " \
       "all-issue-types RTA statement PDF from its live data, and run RtaReconciliationAgent " \
       "against both. Usage: rake \"rta:demo[<fund_id>]\""
  task :demo, [:fund_id] => :environment do |_t, args|
    require Rails.root.join("lib", "rta_demo_generator")

    fund_id = args[:fund_id]
    abort "Usage: rake \"rta:demo[<fund_id>]\"" if fund_id.blank?

    RtaDemoGenerator.new(fund_id).call
  end
end