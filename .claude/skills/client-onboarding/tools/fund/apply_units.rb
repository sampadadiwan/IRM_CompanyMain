# Post-import unit actions for a unit-based fund (imports create no units): through the API only.
#   1. allocate  PATCH /capital_calls/:id/allocate_units          on each APPROVED call whose remittances hold no units yet
#   2. price     PATCH /capital_distributions/:id.json unit_prices on each redemption distribution (face value > 0) without prices
#   3. redeem    PATCH /capital_distributions/:id/redeem_units     on each priced redemption whose payments hold no units yet
# Prices come from mappings/drawdowns.yml › units.price_per_class. Anything already done is skipped, so it is safe to re-run.
# DRY RUN by default (lists the actions); --execute runs them behind the must-have gate (fund + drawdowns for allocating,
# distributions for redeeming) and waits until the unit totals stop changing after each action.
#
# Usage: ruby apply_units.rb [--workspace DIR] [--fund-id ID] [--execute]
require "optparse"
require "yaml"
require_relative "../api"
require_relative "../gate"

api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
opts = { execute: false }
OptionParser.new do |o|
  o.on("--fund-id ID", Integer) { opts[:fund_id] = _1 }
  o.on("--execute") { opts[:execute] = true }
end.parse!(ARGV)
config = YAML.safe_load_file(File.join(api.workspace, "mappings", "drawdowns.yml"), permitted_classes: [Date])
prices = config.dig("units", "price_per_class")
prices = prices["value"] if prices.is_a?(Hash) && prices.key?("value")
abort "✖ no units.price_per_class in mappings/drawdowns.yml — this fund is not unit-based" unless prices

fund_id = opts[:fund_id] || api.list("/funds.json").find { _1["name"] == config.dig("fund", "name") }&.dig("id") or abort "✖ fund not found — pass --fund-id"
in_fund = ->(rows) { rows.select { _1["fund_id"] == fund_id } }
units_of = ->(rows) { rows.sum { _1["units_quantity"].to_f } }
remittances = -> { in_fund.(api.list("/capital_remittances.json?fund_id=#{fund_id}&all=true")) }
dist_payments = -> { in_fund.(api.list("/capital_distribution_payments.json?fund_id=#{fund_id}&all=true")) }

# ── Plan: what is not done yet ──────────────────────────────────────────────────────────────────────────────────────
calls = in_fund.(api.list("/capital_calls.json?fund_id=#{fund_id}&all=true"))
dists = in_fund.(api.list("/capital_distributions.json?fund_id=#{fund_id}&all=true"))
rems, pays = remittances.(), dist_payments.()
plan = []
calls.each do |c|
  rs = rems.select { _1["capital_call_id"] == c["id"] }
  next if units_of.(rs).nonzero?

  plan << (c["approved"] ? [:allocate, c] : [:blocked, c, "call not approved — approve it first"])
end
dists.select { _1["face_value_for_redemption"].to_f.positive? }.each do |d|
  priced = d["unit_prices"].is_a?(Hash) && d["unit_prices"].any?
  plan << [:price, d] unless priced
  next if units_of.(pays.select { _1["capital_distribution_id"] == d["id"] }).nonzero?

  plan << (d["approved"] ? [:redeem, d] : [:blocked, d, "distribution not approved — approve it first"])
end

puts "fund #{fund_id}: units issued #{units_of.(rems).round(4)}, redeemed #{-units_of.(pays).round(4)}, balance #{(units_of.(rems) + units_of.(pays)).round(4)}"
if plan.empty?
  puts "✔ nothing to do — every approved call has units allocated and every redemption is priced and redeemed"
  exit
end
plan.each { |action, rec, why| puts "  #{action == :blocked ? '✖' : '▶'} #{action.to_s.ljust(8)} #{rec['name'] || rec['title']} (id #{rec['id']})#{" — #{why}" if why}" }
unless opts[:execute]
  puts "(dry run — rerun with --execute to apply)"
  exit
end

# ── Execute, behind the gate ────────────────────────────────────────────────────────────────────────────────────────
Onboarding::Gate.check!(api.workspace, :fund) # unit prices (M5)
Onboarding::Gate.check!(api.workspace, :drawdowns) if plan.any? { _1.first == :allocate }
Onboarding::Gate.check!(api.workspace, :distributions) if plan.any? { %i[price redeem].include?(_1.first) }
plan.each do |action, rec, _|
  case action
  when :allocate
    status, = api.call("patch", "/capital_calls/#{rec['id']}/allocate_units.json")
    # Poll this call's remittances only (capital_call_id= is applied by the server; checked 2026-10-20)
    after = api.wait_until_stable { units_of.(in_fund.(api.list("/capital_remittances.json?fund_id=#{fund_id}&all=true&capital_call_id=#{rec['id']}"))).then { _1.nonzero? && _1 } }
    puts "✔ allocate #{rec['name']}: HTTP #{status}, #{after.inspect} units issued"
  when :price
    status, = api.call("patch", "/capital_distributions/#{rec['id']}.json", body: { capital_distribution: { unit_prices: prices.transform_values(&:to_s) } })
    puts "✔ price #{rec['title']}: HTTP #{status}, unit_prices #{prices}"
  when :redeem
    status, = api.call("patch", "/capital_distributions/#{rec['id']}/redeem_units.json")
    # Poll this distribution's payments only: the plain capital_distribution_id= param — q[capital_distribution_id_eq] is
    # silently ignored by this endpoint (returns every payment; checked 2026-10-20)
    after = api.wait_until_stable { units_of.(in_fund.(api.list("/capital_distribution_payments.json?fund_id=#{fund_id}&all=true&capital_distribution_id=#{rec['id']}"))).then { _1.nonzero? && _1 } }
    puts "✔ redeem #{rec['title']}: HTTP #{status}, #{after.inspect} units"
  when :blocked
    puts "✖ skipped #{rec['name'] || rec['title']} — not approved"
  end
end
puts "fund #{fund_id}: balance units now #{(units_of.(remittances.()) + units_of.(dist_payments.())).round(4)}"
