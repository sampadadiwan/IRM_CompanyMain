# Phase 4 steps: the IFSCA pack, a second regime on one entity, and currency conversion.
# Worked examples H13, E8, H24, X25, X68 — openspec/changes/fund-compliance-monitoring/business-rules.md

# The IFSCA pack, published the same way as SEBI's: an ops load of the seed file with the counsel fields filled
Given('the IFSCA pack is published') do
  cmp[:ifsca] ||= begin
    data = JSON.parse(Rails.root.join("db/seeds/compliance/ifsca_fm_v1.json").read)
    data["version"].merge!("effective_from" => "2026-12-01", "counsel_reviewer" => "A. Kapoor", "counsel_reviewed_on" => "2026-11-20")
    travel_to(Time.zone.parse("2026-11-01 10:00")) { CompliancePackLoader.call(data, publish: true) }
  end
end

# E8: the entity's regulator setting (entity_settings.regulatory_env) is informational for compliance packs
Given("Horizon's regulator setting is {string}") do |regime|
  setting = horizon.entity_setting || horizon.create_entity_setting!
  setting.update!(regulatory_env: regime)
end

Then('the attachment saves') do
  expect(@attached).to be(true), @attach.errors.full_messages.to_sentence
end

# H13: the mapping is entered once on the Setup page, whichever packs use the input
When('{string} maps the sponsor\/manager input to {string}') do |user, category|
  params = ActionController::Parameters.new(mappings: { "sponsor" => category }).permit!
  expect(ComplianceSetupUpdate.call(setup: cmp_setup, params:, user: cmp_user(user)).error).to be_nil
end

Then('the inputs list {string} once, used by {string}, mapped') do |label, packs|
  rows = ComplianceInputs.for(horizon).select { |i| i.label == label }
  expect(rows.size).to eq(1)
  expect(rows.first.packs.sort).to eq(packs.split(", ").sort)
  expect(rows.first.mapped).to be(true)
  expect(rows.first.missing?).to be(false)
end

# H24, X25: an INR fund under the USD-denominated IFSCA pack, one investor below the USD minimum
Given('{string} is an INR fund classified {string} under IFSCA with an investor committing ₹{float} cr') do |fund_name, classification, value|
  travel_to(Time.zone.parse("2026-11-01 10:00")) do
    fund = cmp_fund!(horizon, fund_name, start_date: Date.new(2025, 6, 1), currency: "INR")
    investor = cmp_investor!(horizon, "#{fund_name} LP")
    cmp_commit!(fund, investor, cr(value.to_s))
    cmp_attach!(fund, cmp[:ifsca].compliance_pack, classification)
  end
end

Given('the USD to INR rate is {float} on {string}') do |rate, date|
  ExchangeRate.create!(entity_id: horizon.id, from: "USD", to: "INR", rate: BigDecimal(rate.to_s), as_of: cmp_date(date),
                       source: "manual", provider: "User")
end

Then("the result's working records the rate {float} from {string} to {string}") do |rate, from, to|
  fx = @result.working_hash["fx"]
  expect(fx).to include("from" => from, "to" => to)
  expect(fx["rate"].to_d).to eq(BigDecimal(rate.to_s))
end

# X68: limit currency validation
When('Priya adds an amount limit of {int} in {string}') do |value, currency|
  edit_draft { |d| d["checks"].first["limit"] = { "value" => value, "unit" => "amount", "currency" => currency } }
end

When('Priya adds a percentage limit of {int} in {string}') do |value, currency|
  edit_draft { |d| d["checks"].first["limit"] = { "value" => value, "unit" => "pct", "currency" => currency } }
end
