# Step definitions for features/security/dev_pii_scrub.feature (P1 — scrub personal data in development copies).
# docs/security/owasp_2026_11_changes.md › "P1". Reused: "there is a user … for an entity …" (features/common.rb).

# A KYC with known personal values (written past validation so the values are exactly as given)
Given("a scrub test KYC {string} with PAN {string}, bank account {string}, IFSC {string} and birth date {string}") do |name, pan, account, ifsc, birth_date|
  investor = FactoryBot.create(:investor, entity: @entity, investor_name: name,
                                          investor_entity: FactoryBot.create(:entity, entity_type: "Investor"))
  kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, full_name: name)
  kyc.update_columns(PAN: pan, bank_account_number: account, ifsc_code: ifsc, birth_date: Date.parse(birth_date))
  @scrub_kycs ||= {}
  @scrub_kycs[name] = kyc.id
end

# A history row like the ones audited writes when a PAN is edited
Given("its history records the PAN changing from {string} to {string}") do |from, to|
  kyc_id = @scrub_kycs.values.last
  @scrub_audit = Audited::Audit.create!(auditable_type: "InvestorKyc", auditable_id: kyc_id, action: "update",
                                        audited_changes: { "PAN" => [from, to], "full_name" => %w[A B] })
end

Given("the KYC {string} has custom fields {string}") do |name, pairs|
  fields = pairs.split(";").to_h { |pair| pair.split("=", 2) }
  InvestorKyc.find(@scrub_kycs[name]).update_columns(json_fields: fields)
end

When("the development PII scrub runs") do
  @scrub_counts = DevPiiScrubber.new(logger: Logger.new(nil)).call
end

When("the development PII scrub is started with Rails.env {string}") do |env|
  # The environment is passed in, not stubbed: a stubbed Rails.env leaks into the After hooks
  DevPiiScrubber.new(logger: Logger.new(nil), env: ActiveSupport::EnvironmentInquirer.new(env)).call
  @scrub_error = nil
rescue DevPiiScrubber::Refused => e
  @scrub_error = e
end

Then("the PII scrub is refused with {string}") do |text|
  expect(@scrub_error).to be_a(DevPiiScrubber::Refused)
  expect(@scrub_error.message).to include(text)
end

# disable_all only acts in development; the scrub itself also accepts the test database
When("EntitySetting.disable_all runs in development") do
  # Only disable_all's own check is told "development copy"; Rails.env stays test for the rest of the scenario
  allow(EntitySetting).to receive(:development_copy?).and_return(true)
  # It declares its own Chewy strategy, so it also works from a `rails runner` script (no console strategy)
  expect(Chewy).to receive(:strategy).with(:bypass).and_call_original
  EntitySetting.disable_all
end

def scrub_kyc(name)
  InvestorKyc.find(@scrub_kycs[name])
end

Then("the KYC {string} no longer has PAN {string} but has a PAN-shaped value with {string} as 4th letter") do |name, pan, letter|
  value = scrub_kyc(name).PAN
  expect(value).not_to eq(pan)
  expect(value).to match(/\A[A-Z]{3}#{letter}[A-Z]\d{4}[A-Z]\z/)
end

Then("the KYC {string} no longer has bank account {string} but has {int} digits") do |name, account, digits|
  value = scrub_kyc(name).bank_account_number
  expect(value).not_to eq(account)
  expect(value).to match(/\A\d{#{digits}}\z/)
end

Then("the KYC {string} no longer has birth date {string}") do |name, date|
  expect(scrub_kyc(name).birth_date.to_date).not_to eq(Date.parse(date))
end

Then("the KYC {string} still has IFSC {string} and its name") do |name, ifsc|
  kyc = scrub_kyc(name)
  expect(kyc.ifsc_code).to eq(ifsc)
  expect(kyc.full_name).to eq(name)
end

Then("its history shows {string} for the PAN") do |text|
  changes = Audited::Audit.find(@scrub_audit.id).audited_changes
  expect(changes["PAN"]).to eq(text)
  expect(changes["full_name"]).to eq(%w[A B])
end

Then("the KYCs {string} and {string} share the same new PAN") do |first, second|
  a = scrub_kyc(first).PAN
  expect(a).not_to eq("AAAPA1111A")
  expect(scrub_kyc(second).PAN).to eq(a)
end

Then("the KYC {string} custom field {string} is no longer {string}") do |name, key, value|
  expect(scrub_kyc(name).json_fields[key]).not_to eq(value)
  expect(scrub_kyc(name).json_fields[key]).to be_present
end

Then("the KYC {string} custom field {string} is still {string}") do |name, key, value|
  expect(scrub_kyc(name).json_fields[key]).to eq(value)
end

Then("every entity setting is in sandbox mode") do
  expect(EntitySetting.where(sandbox: [false, nil]).count).to eq(0)
end
