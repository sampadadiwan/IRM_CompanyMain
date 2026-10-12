# Steps for openspec/changes/fund-market-data (features/market_data/*.feature).
# Worked examples: openspec/changes/fund-market-data/business-rules.md

# ---------- Phase 1: entity features, fund features, Market Data settings ----------

Given('the entity has market data features {string}') do |flags|
  entity = @user.entity.reload
  flags.split(",").map(&:strip).each { |f| entity.permissions.set(f.to_sym) }
  entity.save!
  @user.reload
end

Given('the entity Market Data settings are {string}') do |kv|
  setting = MarketDataSetting.for_entity(@user.entity)
  key_val = kv.split(";").to_h { |pair| pair.split("=", 2) }
  key_val.each do |k, v|
    case k
    when "fx_providers", "price_providers" then setting.send("#{k}=", v.split(","))
    when "fund_defaults" then setting.fund_defaults = v.split(",").index_with { true }
    else setting.send("#{k}=", v)
    end
  end
  setting.save!
end

When('I open the Market Data settings') do
  visit(market_data_settings_path)
end

Then('I should see the Market Data card') do
  expect(page).to have_content("Market Data")
  expect(page).to have_content("Cross-rate pivot currency")
end

Then('the Market Data settings are {string} to the user') do |state|
  allowed = MarketDataSettingPolicy.new(@user, MarketDataSetting.for_entity(@user.entity)).show?
  expect(allowed).to eq(state == "available")
end

When('I turn on the FX feed with {string} and the price feed with {string} and save') do |fx, prices|
  visit(market_data_settings_path)
  check("market_data_setting_fx_feed_enabled")
  fx.split(",").each { |p| check("fx_provider_#{p}") }
  check("market_data_setting_price_feed_enabled")
  prices.split(",").each { |p| check("price_provider_#{p}") }
  fill_in("market_data_setting_pivot_currency", with: "USD")
  click_on("Save")
end

When('I turn on the price feed with no provider and save') do
  visit(market_data_settings_path)
  check("market_data_setting_price_feed_enabled")
  MarketDataSetting::PRICE_PROVIDERS.each { |p| uncheck("price_provider_#{p}") }
  click_on("Save")
end

When('I set the entity limit {string} to {string} and save') do |field, value|
  visit(market_data_settings_path)
  fill_in("market_data_setting_#{field}", with: value)
  click_on("Save")
end

Then('the entity Market Data settings should have {string}') do |kv|
  setting = MarketDataSetting.for_entity(@user.entity)
  expect(setting).to be_persisted
  kv.split(";").map { |pair| pair.split("=", 2) }.each do |k, v|
    actual = setting.send(k)
    actual = actual.join(",") if actual.is_a?(Array)
    expect(actual.to_s).to eq(v), "#{k}: expected #{v}, got #{actual}"
  end
end

# The fund form is a two-step wizard; Features is on step 2
def open_fund_form_features(fund)
  visit(edit_fund_path(fund))
  click_on("Next")
end

When('I tick the fund features {string} on the fund form and save') do |flags|
  open_fund_form_features(@fund)
  flags.split(",").each { |f| check("fund_features_#{f.strip}") }
  click_on("Save")
  # Wait for the update to finish before anything reads the database
  expect(page).to have_content("Fund was successfully updated.")
end

Then('the fund features should include {string}') do |flags|
  @fund.reload
  flags.split(",").each { |f| expect(@fund.features.set?(f.strip.to_sym)).to be(true), "#{f} not set" }
end

Then('the fund features should not include {string}') do |flags|
  @fund.reload
  flags.split(",").each { |f| expect(@fund.features.set?(f.strip.to_sym)).to be(false), "#{f} set" }
end

Then('the fund audit trail should record the features change') do
  expect(@fund.reload.audits.any? { |a| a.audited_changes.key?("features") }).to be(true)
end

Then('the fund form should show Manual as always accepted') do
  open_fund_form_features(@fund)
  expect(page).to have_css("#fund_features_manual_rates[disabled][checked]")
  expect(page).to have_css("#fund_features_manual_prices[disabled][checked]")
end

Then('the fund form should {string} the switch {string}') do |show, flag|
  open_fund_form_features(@fund)
  if show == "show"
    expect(page).to have_css("#fund_features_#{flag}")
  else
    expect(page).to have_no_css("#fund_features_#{flag}", visible: :all)
  end
end

Then('the fund form should not show the Limits group') do
  open_fund_form_features(@fund)
  expect(page).to have_content("Features")
  expect(page).to have_no_content("Limits (open-ended)")
end

When('a fund is created in the entity') do
  @fund = Fund.new(entity_id: @user.entity_id, name: "New Fund #{rand(1000)}", currency: "INR", unit_types: "A")
  @fund.save!
end

When('the fund features {string} are submitted directly') do |flags|
  @guard_result = FundFeatureGuard.call(@fund.reload, flags.split(","))
end

Then('the submission should be refused and the fund features unchanged') do
  expect(@guard_result.refused).not_to be_empty
  before = @fund.features.to_a
  expect(@fund.reload.features.to_a).to eq(before)
end

Given('the fund has the old switches {string} stored in columns') do |kv|
  # Raw column values as they were before the flags existed (bypasses the flag accessors)
  attrs = kv.split(";").to_h { |pair| pair.split("=", 2) }.transform_values { |v| v == "true" }
  @fund.update_columns(attrs.merge("features" => 0))
end

When('the fund features backfill runs') do
  Fund.connection.execute(FundEnabled::LEGACY_BACKFILL_SQL)
end

When('a fund is imported with {string}') do |kv|
  row = kv.split(";").to_h { |pair| pair.split("=", 2) }
  row = { "Name" => "Imported Fund", "Currency" => "INR", "Unit Types" => "A" }.merge(row)
  upload = ImportUpload.new(entity: @user.entity)
  ImportFund.new.save_row(row, upload, [])
  @fund = @user.entity.funds.find_by(name: "Imported Fund")
end

Then('the effective fund limits should be {string}') do |kv|
  limits = MarketDataSetting.limits_for(@fund.reload)
  kv.split(";").map { |pair| pair.split("=", 2) }.each do |k, v|
    expect(limits.public_send(k).to_s.to_f).to eq(v.to_f)
  end
end

When('support turns off the entity feature {string}') do |flag|
  entity = @user.entity.reload
  entity.permissions.unset(flag.to_sym)
  entity.save!
end

Then('the fund should {string} the feature {string}') do |state, flag|
  expect(@fund.reload.feature_enabled?(flag.to_sym)).to eq(state == "use")
end

Then('the saved licence and settings never appear in the audit as secrets') do
  # No secrets are stored in this change; the settings audit lists only plain settings
  setting = MarketDataSetting.for_entity(@user.entity)
  expect(setting.audits.flat_map { |a| a.audited_changes.keys }).not_to include("vendor_api_key")
end

When('a non-support company user opens the admin entity form') do
  # Entity features are edited only in Admin (Administrate), which admits super/support only
  @entity_before = @user.entity.reload.permissions.raw
  visit(edit_admin_entity_path(@user.entity))
end

Then('the entity features change is refused') do
  expect(page).to have_content("Not authorized.")
  expect(@user.entity.reload.permissions.raw).to eq(@entity_before)
end

Then('the entity should have the features {string}') do |flags|
  entity = @user.entity.reload
  flags.split(",").each { |f| expect(entity.permissions.set?(f.strip.to_sym)).to be(true), f }
end

# ---------- Phase 2: FX sources, resolver, gain split ----------

def md_funds
  @md_funds ||= {}
end

# Always a fresh record, so its entity's flags are current
def md_fund(name)
  md_funds[name] ? Fund.find(md_funds[name].id) : Fund.find_by!(entity_id: @user.entity_id, name:)
end

def md_date(str)
  Date.parse(str)
end

def md_money_cents(str)
  BigDecimal(str.delete("₹$,")) * 100
end

Given('these funds exist with rate sources:') do |table|
  # | fund | currency | sources | prices |   (sources: manual,market,derived,own)
  entity = @user.entity.reload
  table.hashes.each do |row|
    fund = FactoryBot.build(:fund, entity_id: entity.id, name: row["fund"], currency: row["currency"] || "INR")
    fund.save!
    sources = row["sources"].to_s.split(",").map(&:strip)
    if sources.include?("market")
      entity.permissions.set(:enable_market_rates)
      fund.features.set(:accept_market_rates)
    end
    fund.features.set(:accept_derived_rates) if sources.include?("derived")
    fund.features.set(:use_own_fx_rates) if sources.include?("own")
    if row["prices"].to_s.include?("market")
      entity.permissions.set(:enable_market_prices)
      fund.features.set(:accept_market_prices)
    end
    fund.save!
    md_funds[row["fund"]] = fund
  end
  entity.save!
end

Given('these exchange rates exist:') do |table|
  # | from | to | rate | as_of | source | provider | fund |
  table.hashes.each do |row|
    owner = row["fund"].present? ? md_fund(row["fund"]) : nil
    ExchangeRate.create!(entity_id: @user.entity_id, from: row["from"], to: row["to"], rate: row["rate"],
                         as_of: md_date(row["as_of"]), source: row["source"].presence || "manual",
                         provider: row["provider"].presence || "User", owner:)
  end
end

When('{string} resolves {string} on {string}') do |fund_name, pair, date|
  from, to = pair.split("→")
  fund = md_fund(fund_name)
  @resolution = FxRateResolver.lookup(entity_id: fund.entity_id, from:, to:, as_of: md_date(date), policy: SourcePolicy.for(fund))
end

Then('the rate used should be {string} {string}') do |rate, label|
  expect(@resolution).not_to be_nil
  expect(@resolution.rate.to_d.round(8)).to eq(BigDecimal(rate))
  expect([@resolution.source.capitalize, @resolution.provider].compact.join(" · ")).to eq(label) if label.present?
end

Then('the rate used should be dated {string}') do |date|
  expect(@resolution.as_of).to eq(md_date(date))
end

Then('no rate should be found') do
  expect(@resolution).to be_nil
end

Given('{string} holds {int} {string} \\({word}) bought at {string} each on {string}') do |fund_name, qty, instrument_name, currency, price, date|
  fund = md_fund(fund_name)
  entity = @user.entity
  @portfolio_company ||= begin
    steps %(Given there is an existing portfolio company "name=Market Holdings;category=Portfolio Company")
    @portfolio_company
  end
  instrument = InvestmentInstrument.find_by(entity_id: entity.id, name: instrument_name) ||
               InvestmentInstrument.create!(entity:, portfolio_company: @portfolio_company, name: instrument_name,
                                            currency:, category: "Unlisted", sub_category: "Equity", sector: "Tech")
  pi = FactoryBot.build(:portfolio_investment, entity:, fund:, investment_instrument: instrument,
                                               portfolio_company: @portfolio_company, investment_date: md_date(date),
                                               quantity: qty, ex_expenses_base_amount_cents: md_money_cents(price) * qty)
  @pi_result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  @last_pi = pi
end

Given('the holding was saved') do
  expect(@pi_result.success?).to be(true), @last_pi.errors.full_messages.join(", ")
end

Then('saving the holding should be refused with the missing-rate message for {string} on {string} and sources {string}') do |pair, date, sources|
  from, to = pair.split("→")
  expect(@pi_result.success?).to be(false)
  expected = "No #{from}→#{to} rate on or before #{I18n.l(md_date(date))} in this fund's accepted sources (#{sources}). " \
             "Enter a manual rate, or accept derived rates for this fund."
  expect(@last_pi.errors.full_messages.join(" ")).to include(expected)
end

Given('{string} has a valuation of {string} per share on {string}') do |instrument_name, price, date|
  instrument = InvestmentInstrument.find_by!(entity_id: @user.entity_id, name: instrument_name)
  FactoryBot.create(:valuation, entity: @user.entity, owner: instrument.portfolio_company, investment_instrument: instrument,
                                valuation_date: md_date(date), per_share_value_cents: md_money_cents(price))
end

def md_api(fund_name, instrument_name)
  fund = md_fund(fund_name)
  AggregatePortfolioInvestment.joins(:investment_instrument).find_by!(fund_id: fund.id, investment_instruments: { name: instrument_name })
end

Then('the fair value of {string} in {string} on {string} should be {string}') do |instrument_name, fund_name, date, amount|
  api = md_api(fund_name, instrument_name)
  expect((api.fmv_on_date(md_date(date)) / 100).round(2)).to eq((md_money_cents(amount) / 100).round(2))
end

When('the holdings of {string} are recomputed') do |fund_name|
  md_fund(fund_name).portfolio_investments.find_each { |pi| PortfolioInvestmentUpdate.call(portfolio_investment: pi) }
end

Then('the {string} holding in {string} should show gain {string} = price effect {string} + currency effect {string}') do |instrument_name, fund_name, gain, price, fx|
  pi = md_fund(fund_name).portfolio_investments.joins(:investment_instrument).where(investment_instruments: { name: instrument_name }).buys.first.reload
  expect(pi.unrealized_gain_cents.to_d.round(2)).to eq(md_money_cents(gain).round(2))
  expect(pi.unrealized_price_effect_cents.to_d.round(2)).to eq(md_money_cents(price).round(2))
  expect(pi.unrealized_fx_effect_cents.round(2)).to eq(md_money_cents(fx).round(2))
end

Then('the {string} holding in {string} gain split should add up exactly') do |instrument_name, fund_name|
  pi = md_fund(fund_name).portfolio_investments.joins(:investment_instrument).where(investment_instruments: { name: instrument_name }).buys.first.reload
  local_gain = pi.instrument_currency_unrealized_gain_cents.to_d
  rate = pi.fmv_cents.to_d / pi.instrument_currency_fmv_cents.to_d
  expect(pi.unrealized_price_effect_cents.to_d).to eq((local_gain * rate).round(2))
  expect(pi.unrealized_price_effect_cents.to_d + pi.unrealized_fx_effect_cents).to eq(pi.unrealized_gain_cents.to_d)
end

When('{string} sells {int} {string} at {string} each on {string}') do |fund_name, qty, instrument_name, price, date|
  fund = md_fund(fund_name)
  instrument = InvestmentInstrument.find_by!(entity_id: @user.entity_id, name: instrument_name)
  pi = FactoryBot.build(:portfolio_investment, entity: @user.entity, fund:, investment_instrument: instrument,
                                               portfolio_company: instrument.portfolio_company, investment_date: md_date(date),
                                               quantity: -qty, ex_expenses_base_amount_cents: md_money_cents(price) * qty)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  expect(result.success?).to be(true), pi.errors.full_messages.join(", ")
  @sale = pi
end

Then('the sale should show realised gain {string} = price effect {string} + currency effect {string}') do |gain, price, fx|
  sale = @sale.reload
  expect(sale.gain_cents.to_d.round(2)).to eq(md_money_cents(gain).round(2))
  expect(sale.realized_price_effect_cents.to_d.round(2)).to eq(md_money_cents(price).round(2))
  expect(sale.realized_fx_effect_cents.round(2)).to eq(md_money_cents(fx).round(2))
end

Then('all exchange rates of the entity should be Manual') do
  expect(ExchangeRate.where(entity_id: @user.entity_id).distinct.pluck(:source)).to eq(["manual"])
end

Then('the entity should list {int} {string} rates for {string} on {string}') do |count, _label, pair, date|
  from, to = pair.split("→")
  expect(ExchangeRate.where(entity_id: @user.entity_id, from:, to:, as_of: md_date(date)).where.not(source: "derived").count).to eq(count)
end

Then('a derived rate {string} should be stored as {string}') do |pair, provider|
  from, to = pair.split("→")
  row = ExchangeRate.find_by!(entity_id: @user.entity_id, from:, to:, source: "derived", provider:)
  expect(row.leg1_id).to be_present
end

When('a manual {string} rate of {string} is added for {string}') do |pair, rate, date|
  from, to = pair.split("→")
  ExchangeRate.create!(entity_id: @user.entity_id, from:, to:, rate:, as_of: md_date(date), source: "manual", provider: "User")
end

Then('storing a derived rate should start no jobs') do
  expect(ExchangeRatePortfolioInvestmentJob).not_to receive(:perform_later)
  expect(ExchangeRateCommitmentAdjustmentJob).not_to receive(:perform_later)
  ExchangeRate.where(source: "derived").delete_all
  steps %(When "Bridge Hybrid Fund" resolves "EUR→INR" on "30 Oct 2026")
  expect(ExchangeRate.where(source: "derived").count).to eq(1)
end

Then('a same-currency conversion should use rate 1 without a lookup') do
  expect(ExchangeRate).not_to receive(:where)
  r = FxRateResolver.lookup(entity_id: @user.entity_id, from: "INR", to: "INR", as_of: Time.zone.today, policy: SourcePolicy.manual_only)
  expect(r.rate).to eq(1)
end

Then('an entity-level {string} conversion on {string} should use {string}') do |pair, date, rate|
  from, to = pair.split("→")
  expect(ExchangeRate.get_rate(from, to, md_date(date), @user.entity_id).to_d).to eq(BigDecimal(rate))
end

# E28 — the allocation engine resolves on its scratch SQLite copy exactly as the live screens do
Then('the allocation copy should resolve {string} for {string} on {string} like the live screens') do |pair, fund_name, date|
  from, to = pair.split("→")
  fund = md_fund(fund_name)
  policy = SourcePolicy.for(fund)
  live = FxRateResolver.lookup(entity_id: fund.entity_id, from:, to:, as_of: md_date(date), policy:)
  path = Rails.root.join("tmp", "md_scratch_#{Process.pid}_#{rand(100_000)}.sqlite3").to_s
  scratch = Object.new.extend(AccountEntryAllocation::WithScratchSqlite)
  copy = nil
  scratch.with_scratch_sqlite(path) do
    conn = ExchangeRateSqlite.connection
    conn.create_table(:exchange_rates, force: true) do |t|
      t.date :as_of
      t.decimal :decimal, precision: 20, scale: 8, default: 0
      t.bigint :document_folder_id
      t.bigint :entity_id, null: false
      t.string :from, limit: 5
      t.bigint :import_upload_id
      t.boolean :latest, default: true
      t.text :notes
      t.decimal :rate, precision: 20, scale: 8, default: 0
      t.string :to, limit: 5
      t.string :source, null: false, default: "manual"
      t.string :provider
      t.string :rate_type, null: false, default: "reference"
      t.string :owner_type
      t.bigint :owner_id
      t.bigint :leg1_id
      t.bigint :leg2_id
      t.timestamps
    end
    rows = ExchangeRate.where(entity_id: fund.entity_id).where.not(source: "derived").map { |r| r.attributes.except("id") }
    ExchangeRateSqlite.insert_all!(rows)
    copy = FxRateResolver.lookup(entity_id: fund.entity_id, from:, to:, as_of: md_date(date), policy:, model: ExchangeRateSqlite)
  end
  FileUtils.rm_f(Dir["#{path}*"])
  expect(copy.rate.to_d).to eq(live.rate.to_d)
  expect(copy.source).to eq(live.source)
end

When('a market {string} rate of {string} arrives for {string} while tracking recomputes') do |pair, rate, date|
  from, to = pair.split("→")
  @recomputed_fund_ids = []
  allow(PortfolioInvestmentUpdate).to receive(:call).and_wrap_original do |m, **kw|
    @recomputed_fund_ids << kw[:portfolio_investment].fund_id
    m.call(**kw)
  end
  ExchangeRate.create!(entity_id: @user.entity_id, from:, to:, rate:, as_of: md_date(date), source: "market", provider: "ECB via EUR")
end

When('a manual {string} rate of {string} for {string} arrives for {string} while tracking recomputes') do |pair, rate, fund_name, date|
  from, to = pair.split("→")
  @recomputed_fund_ids = []
  allow(PortfolioInvestmentUpdate).to receive(:call).and_wrap_original do |m, **kw|
    @recomputed_fund_ids << kw[:portfolio_investment].fund_id
    m.call(**kw)
  end
  ExchangeRate.create!(entity_id: @user.entity_id, from:, to:, rate:, as_of: md_date(date), source: "manual", provider: "User", owner: md_fund(fund_name))
end

Then('holdings of {string} should be recomputed and holdings of {string} should not') do |yes, no|
  expect(@recomputed_fund_ids.uniq).to include(md_fund(yes).id)
  expect(@recomputed_fund_ids.uniq).not_to include(md_fund(no).id)
end

Given('the entity uses the exchange-rate commitment adjustment option') do
  e = @user.entity.reload
  e.customization_flags.set(:enable_exchange_rate_commitment_adjustment)
  e.save!
end

Then('a market {string} rate arriving for {string} should not start a commitment adjustment') do |pair, date|
  from, to = pair.split("→")
  expect(ExchangeRateCommitmentAdjustmentJob).not_to receive(:perform_later)
  ExchangeRate.create!(entity_id: @user.entity_id, from:, to:, rate: "85.1", as_of: md_date(date), source: "market", provider: "ECB via EUR")
end

Then('a manual {string} rate for {string} arriving on {string} should start a commitment adjustment') do |pair, fund_name, date|
  from, to = pair.split("→")
  expect(ExchangeRateCommitmentAdjustmentJob).to receive(:perform_later).once
  ExchangeRate.create!(entity_id: @user.entity_id, from:, to:, rate: "84.4", as_of: md_date(date), source: "manual", provider: "User", owner: md_fund(fund_name))
end

When('fund staff turn on {string} for {string}') do |flag, fund_name|
  fund = md_fund(fund_name).reload
  @booked_before = fund.portfolio_investments.pluck(:id, :amount_cents).to_h
  fund.features.set(flag.to_sym)
  fund.save!
end

Then('the booked cost of every holding in {string} should be unchanged') do |fund_name|
  after = md_fund(fund_name).portfolio_investments.pluck(:id, :amount_cents).to_h
  expect(after).to eq(@booked_before)
end

When('a second manual {string} rate is added for {string}') do |pair, date|
  from, to = pair.split("→")
  @dup_rate = ExchangeRate.new(entity_id: @user.entity_id, from:, to:, rate: "84", as_of: md_date(date), source: "manual", provider: "User")
end

Then('it should be refused as a duplicate') do
  expect(@dup_rate.save).to be(false)
  expect(@dup_rate.errors[:as_of]).to include("has already been taken")
end

When('an exchange-rate upload row names the fund {string}') do |fund_name|
  upload = ImportUpload.new(entity: @user.entity)
  row = { "From" => "USD", "To" => "INR", "Rate" => "84.1", "As Of" => "2026-10-30", "Notes" => "", "Fund" => fund_name }
  @upload_error = nil
  begin
    ImportExchangeRate.new.save_row(row, upload, [], {})
  rescue StandardError => e
    @upload_error = e.message
  end
end

Then('the upload row should be refused with {string}') do |message|
  expect(@upload_error).to eq(message)
end

Given('another entity has a fund {string}') do |fund_name|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Entity #{rand(1000)}")
  FactoryBot.create(:fund, entity: other, name: fund_name)
end

Then('the exchange rates dated before {string} should all be Manual') do |date|
  rows = ExchangeRate.where(entity_id: @user.entity_id).where(as_of: ...md_date(date))
  expect(rows.exists?).to be(true)
  expect(rows.distinct.pluck(:source)).to eq(["manual"])
end

When('fund staff turn off {string} for {string}') do |flag, fund_name|
  fund = md_fund(fund_name).reload
  fund.features.unset(flag.to_sym)
  fund.save!
end

Then('the derived rate should belong to {string}') do |fund_name|
  expect(@resolution.row.owner_type).to eq("Fund")
  expect(@resolution.row.owner_id).to eq(md_fund(fund_name).id)
end

Given('the manual {string} rates are removed') do |pair|
  from, to = pair.split("→")
  ExchangeRate.where(entity_id: @user.entity_id, from:, to:, source: "manual").delete_all
end

# ---------- Phase 3: FX rate feed ----------

def stub_ecb(status: 200)
  # WebMock helpers are added by the @sync-http hook; make sure this World has them
  singleton_class.include(WebMock::API) unless respond_to?(:stub_request)
  singleton_class.include(WebMock::Matchers) unless respond_to?(:a_request)
  body = Rails.root.join("features/support/fixtures/market_data/ecb_hist.xml").read
  stub_request(:get, EcbProvider::URL).to_return(status:, body: status == 200 ? body : "error")
end

Given('the FX feed is on with the ECB provider') do
  entity = @user.entity.reload
  entity.permissions.set(:enable_market_rates)
  entity.save!
  setting = MarketDataSetting.for_entity(entity)
  setting.assign_attributes(fx_feed_enabled: true, fx_providers: ["ecb"])
  setting.save!
end

Given('the entity holds a {string} instrument in an INR fund') do |currency|
  @md_fund ||= FactoryBot.create(:fund, entity_id: @user.entity_id, name: "Feed Fund #{rand(1000)}", currency: "INR")
  @portfolio_company ||= begin
    steps %(Given there is an existing portfolio company "name=Feed Holdings;category=Portfolio Company")
    @portfolio_company
  end
  InvestmentInstrument.create!(entity: @user.entity, portfolio_company: @portfolio_company, name: "#{currency} Holding #{rand(1000)}",
                               currency:, category: "Unlisted", sub_category: "Equity", sector: "Tech")
end

When('the FX feed runs for {string}') do |date|
  stub_ecb
  FxFeedJob.perform_now(md_date(date).iso8601)
end

When('the FX feed runs for {string} while the provider is down') do |date|
  stub_ecb(status: 500)
  FxFeedJob.perform_now(md_date(date).iso8601)
end

Then('a Market {string} rate of {string} from {string} dated {string} should exist') do |pair, rate, provider, date|
  from, to = pair.split("→")
  row = ExchangeRate.find_by!(entity_id: @user.entity_id, from:, to:, as_of: md_date(date), source: "market")
  expect(row.rate.to_d).to eq(BigDecimal(rate))
  expect(row.provider).to eq(provider)
  expect(row.rate_type).to eq("reference")
end

Then('there should be {int} Market {string} rate(s) dated {string}') do |count, pair, date|
  from, to = pair.split("→")
  expect(ExchangeRate.where(entity_id: @user.entity_id, from:, to:, as_of: md_date(date), source: "market").count).to eq(count)
end

Then('the {string} run for {string} should be {string}') do |provider, date, status|
  runs = MarketDataRun.where(entity_id: @user.entity_id, provider:, run_date: md_date(date))
  expect(runs.count).to eq(1)
  expect(runs.first.status).to eq(status)
end

Then('the run for {string} should list missing {string}') do |date, keys|
  run = MarketDataRun.find_by!(entity_id: @user.entity_id, run_date: md_date(date))
  expect(run.missing_items.map { |m| m["key"].sub("/", "→") }.sort).to eq(keys.split(",").map(&:strip).sort)
end

Then('no FX feed run should exist for {string}') do |date|
  singleton_class.include(WebMock::Matchers) unless respond_to?(:a_request)
  expect(MarketDataRun.where(entity_id: @user.entity_id, run_date: md_date(date))).to be_none
  expect(a_request(:get, EcbProvider::URL)).not_to have_been_made
end

Then('the FX feed should track the pair {string}') do |pair|
  expect(MarketDataPairsInUse.for(@user.entity.reload)).to include(pair.sub("→", "/"))
end

Then('{int} feed email(s) with subject {string} should have been sent') do |count, subject|
  mails = ActionMailer::Base.deliveries.select { |m| m.subject == subject }
  expect(mails.size).to eq(count)
end

When('an exchange-rate upload has a row without a Source column') do
  upload = ImportUpload.new(entity: @user.entity)
  row = { "From" => "CHF", "To" => "INR", "Rate" => "96.5", "As Of" => "2026-10-30", "Notes" => "" }
  ImportExchangeRate.new.save_row(row, upload, [], {})
end

Then('the uploaded rate should be Manual with provider {string}') do |provider|
  row = ExchangeRate.find_by!(entity_id: @user.entity_id, from: "CHF", to: "INR")
  expect(row.source).to eq("manual")
  expect(row.provider).to eq(provider)
end

Given('a second entity {string} also runs the ECB feed with an INR fund holding USD') do |name|
  @first_user = @user
  @md_fund = nil
  @portfolio_company = nil
  steps %(Given there is a user "" for an entity "name=#{name};entity_type=Investment Fund;currency=INR")
  steps %(Given the FX feed is on with the ECB provider)
  steps %(Given the entity holds a "USD" instrument in an INR fund)
  @second_user = @user
  @user = @first_user
  @md_fund = nil
  @portfolio_company = nil
end

When('the market USD→INR row of the first entity is deleted') do
  ExchangeRate.where(entity_id: @first_user.entity_id, from: "USD", to: "INR", source: "market").delete_all
end

Then('the second entity should still have its own Market USD→INR rate for {string}') do |date|
  rows = ExchangeRate.where(entity_id: @second_user.entity_id, from: "USD", to: "INR", as_of: md_date(date), source: "market")
  expect(rows.count).to eq(1)
  expect(rows.first.rate.to_d).to eq(BigDecimal("85"))
end

# ---------- Phase 4: instruments and price sources ----------

def md_instrument(name)
  InvestmentInstrument.find_by!(entity_id: @user.entity_id, name:)
end

Given('the price feed is on with providers {string}') do |providers|
  entity = @user.entity.reload
  entity.permissions.set(:enable_market_prices)
  entity.save!
  setting = MarketDataSetting.for_entity(entity)
  setting.assign_attributes(price_feed_enabled: true, price_providers: providers.split(","))
  setting.save!
end

Given('there is an INR instrument {string}') do |name|
  @portfolio_company ||= begin
    steps %(Given there is an existing portfolio company "name=Market Holdings;category=Portfolio Company")
    @portfolio_company
  end
  InvestmentInstrument.create!(entity: @user.entity, portfolio_company: @portfolio_company, name:, currency: "INR",
                               category: "Unlisted", sub_category: "Equity", sector: "Tech")
end

When('the instrument {string} is set to {string}') do |name, kv|
  @instrument = md_instrument(name)
  attrs = kv.split(";").to_h { |pair| pair.split("=", 2) }
  @instrument_saved = @instrument.update(attrs)
end

Then('the instrument should be saved as Market priced') do
  expect(@instrument_saved).to be(true), @instrument.errors.full_messages.join(", ")
  expect(@instrument.reload.market_priced?).to be(true)
end

Then('the instrument should be refused with {string}') do |message|
  expect(@instrument_saved).to be(false)
  expect(@instrument.errors.full_messages.join(" | ")).to include(message)
end

Given('{string} has a {word} price of {string} on {string}') do |name, source, price, date|
  instrument = md_instrument(name)
  FactoryBot.create(:valuation, entity: @user.entity, owner: instrument.portfolio_company, investment_instrument: instrument,
                                valuation_date: md_date(date), per_share_value_cents: md_money_cents(price),
                                source:, provider: { "manual" => "User", "market" => "NSE", "cost" => "Purchase" }[source])
end

Then('{string} should use a price of {string} per share for {string} on {string}') do |fund_name, price, instrument_name, date|
  fund = md_fund(fund_name)
  r = PriceResolver.lookup(instrument: md_instrument(instrument_name), owner: md_instrument(instrument_name).portfolio_company,
                           as_of: md_date(date), policy: SourcePolicy.for(fund))
  expect(r).not_to be_nil
  expect(r.value_cents.to_d).to eq(md_money_cents(price))
  @price_resolution = r
end

Then('the price used should come from {string}') do |source|
  expect(@price_resolution.source).to eq(source)
end

Then('{string} should have a {word} price of {string} on {string}') do |name, source, price, date|
  v = Valuation.find_by!(investment_instrument_id: md_instrument(name).id, valuation_date: md_date(date), source:)
  expect(v.per_share_value_cents.to_d).to eq(md_money_cents(price))
end

Given('the instrument {string} has the SEBI ISIN {string}') do |name, isin|
  instrument = md_instrument(name)
  instrument.update_columns(json_fields: instrument.json_fields.to_h.merge("sebi_isin" => isin), isin: nil)
end

When('the ISIN backfill runs') do
  InvestmentInstrument.copy_sebi_isins!
end

Then('the instrument {string} should have ISIN {string} and pricing method {string}') do |name, isin, method|
  instrument = md_instrument(name)
  expect(instrument.isin).to eq(isin)
  expect(instrument.pricing_method).to eq(method)
end

Then('{string} should have {int} valuations') do |name, count|
  expect(Valuation.where(investment_instrument_id: md_instrument(name).id).count).to eq(count)
end

Then('a valuation created without a source for {string} should be Manual') do |name|
  instrument = md_instrument(name)
  v = FactoryBot.create(:valuation, entity: @user.entity, owner: instrument.portfolio_company, investment_instrument: instrument,
                                    valuation_date: Date.new(2026, 1, 15), per_share_value_cents: 100_000)
  expect(v.reload.source).to eq("manual")
end

When('a valuation upload row for {string} has Price Type {string}') do |name, price_type|
  instrument = md_instrument(name)
  upload = ImportUpload.new(entity: @user.entity)
  row = { "Instrument" => name, "Valuation Date" => "2026-09-15", "Valuation" => "0", "Per Share Value" => "1111",
          "Portfolio Company" => instrument.portfolio_company.investor_name, "Price Type" => price_type }
  ImportValuation.new.save_row(row, upload, [], {})
end

Then('the uploaded valuation for {string} should be Manual with price type {string}') do |name, price_type|
  v = Valuation.find_by!(investment_instrument_id: md_instrument(name).id, valuation_date: Date.new(2026, 9, 15))
  expect(v.source).to eq("manual")
  expect(v.price_type).to eq(price_type)
end

When('a second manual valuation is added for {string} on {string}') do |name, date|
  instrument = md_instrument(name)
  @dup_valuation = FactoryBot.build(:valuation, entity: @user.entity, owner: instrument.portfolio_company, investment_instrument: instrument,
                                                valuation_date: md_date(date), per_share_value_cents: 99_900, source: "manual")
end

Then('the valuation should be refused as a duplicate') do
  expect(@dup_valuation.save).to be(false)
  expect(@dup_valuation.errors[:valuation_date]).to include("has already been taken")
end

# ---------- Phase 5: price feed and corporate actions ----------

def md_udiff_csv(rows)
  header = "TradDt,BizDt,Sgmt,Src,FinInstrmTp,FinInstrmId,ISIN,TckrSymb,SctySrs,XpryDt,FininstrmActlXpryDt,StrkPric,OptnTp,FinInstrmNm,OpnPric,HghPric,LwPric,ClsPric,LastPric,PrvsClsgPric,UndrlygPric,SttlmPric,OpnIntrst,ChngInOpnIntrst,TtlTradgVol,TtlTrfVal,TtlNbOfTxsExctd,SsnId,NewBrdLotQty,Rmks,Rsvd1,Rsvd2,Rsvd3,Rsvd4"
  lines = rows.map do |r|
    ["2026-10-30", "2026-10-30", r[:sgmt] || "CM", "NSE", r[:type] || "STK", "1", r[:isin], r[:ticker], r[:series] || "EQ",
     r[:expiry], r[:expiry], r[:strike], r[:option_type], r[:name] || r[:ticker], "0", "0", "0", r[:close], r[:close], "0", "0",
     r[:settle] || r[:close], "0", "0", "0", "0", "0", "F1", r[:lot] || "1", "", "", "", "", ""].join(",")
  end
  ([header] + lines).join("\n")
end

def md_zip(name, content)
  buffer = Zip::OutputStream.write_buffer do |zip|
    zip.put_next_entry(name)
    zip.write(content)
  end
  buffer.string
end

def md_webmock!
  singleton_class.include(WebMock::API) unless respond_to?(:stub_request)
  singleton_class.include(WebMock::Matchers) unless respond_to?(:a_request)
end

Given('NSE reports these closes for {string}:') do |date, table|
  md_webmock!
  rows = table.hashes.map { |h| { ticker: h["ticker"], close: h["close"] } }
  url = NseEquityProvider.new.url(md_date(date))
  stub_request(:get, url).to_return(status: 200, body: md_zip("bhav.csv", md_udiff_csv(rows)))
end

Given('AMFI reports a NAV of {string} for ISIN {string} on {string}') do |nav, isin, date|
  md_webmock!
  # The real NAVAll.txt layout: 6 semicolon-separated columns, with section headings between blocks
  body = "Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date\n \n" \
         "Open Ended Schemes(Liquid Scheme)\n \nSample Mutual Fund\n \n" \
         "119551;#{isin};-;Sample Liquid Fund - Direct Plan - Growth;#{nav};#{md_date(date).strftime('%d-%b-%Y')}\n"
  stub_request(:get, AmfiProvider::URL).to_return(status: 200, body:)
end

Given('NSE reports these corporate actions:') do |table|
  md_webmock!
  rows = table.hashes.map do |h|
    { "symbol" => h["ticker"], "subject" => h["subject"], "exDate" => md_date(h["ex_date"]).strftime("%d-%b-%Y"), "series" => "EQ" }
  end
  stub_request(:get, NseCorporateActionsProvider::HOME).to_return(status: 200, body: "", headers: { "Set-Cookie" => "nsit=abc; Path=/" })
  stub_request(:get, /#{Regexp.escape(NseCorporateActionsProvider::API)}/o).to_return(status: 200, body: rows.to_json)
end

Given('NSE reports no corporate actions') do
  steps %(Given NSE reports these corporate actions:
    | ticker | subject | ex_date |)
end

Given('there is a Market instrument {string} on {string} with ticker {string}') do |name, exchange, ticker|
  steps %(Given there is an INR instrument "#{name}")
  md_instrument(name).update!(ticker:, exchange:, pricing_method: "market")
end

Given('there is a Market mutual fund {string} with ISIN {string}') do |name, isin|
  steps %(Given there is an INR instrument "#{name}")
  md_instrument(name).update!(isin:, pricing_method: "market")
end

When('the price feed runs for {string}') do |date|
  md_webmock!
  stub_request(:get, NseCorporateActionsProvider::HOME).to_return(status: 200, body: "") unless WebMock::StubRegistry.instance.registered_request?(WebMock::RequestSignature.new(:get, NseCorporateActionsProvider::HOME))
  PriceFeedJob.perform_now(md_date(date).iso8601)
end

When('the price feed runs for {string} while counting recomputes') do |date|
  @recomputed_pi_ids = []
  allow(PortfolioInvestmentUpdate).to receive(:call).and_wrap_original do |m, **kw|
    @recomputed_pi_ids << kw[:portfolio_investment].id
    m.call(**kw)
  end
  steps %(When the price feed runs for "#{date}")
end

Then('each holding should have been recomputed once') do
  counts = @recomputed_pi_ids.tally
  expect(counts).not_to be_empty
  expect(counts.values.uniq).to eq([1])
end

Then('{string} should have {int} market valuation(s) on {string}') do |name, count, date|
  expect(Valuation.where(investment_instrument_id: md_instrument(name).id, valuation_date: md_date(date), source: "market").count).to eq(count)
end

Then('the market price of {string} on {string} should be {string} from {string}') do |name, date, price, provider|
  v = Valuation.find_by!(investment_instrument_id: md_instrument(name).id, valuation_date: md_date(date), source: "market")
  expect(v.per_share_value_cents.to_d).to eq(md_money_cents(price))
  expect(v.provider).to eq(provider)
  expect(v.price_type).to eq("close")
end

Then('the {string} price run for {string} should list {string}') do |provider, date, text|
  run = MarketDataRun.find_by!(entity_id: @user.entity_id, kind: "prices", provider:, run_date: md_date(date))
  expect(run.missing_items.map { |m| "#{m['name']} — #{m['reason']}" }).to include(text)
end

Then('{int} email(s) should mention {string}') do |count, text|
  expect(ActionMailer::Base.deliveries.count { |m| m.body.encoded.include?(text) || m.subject.to_s.include?(text) }).to eq(count)
end

Then('there should be {int} {word} corporate action suggestion(s) for {string}') do |count, status, name|
  expect(CorporateActionSuggestion.where(investment_instrument_id: md_instrument(name).id, status:).count).to eq(count)
end

When('the suggestion for {string} is {word} by the user') do |name, action|
  s = CorporateActionSuggestion.find_by!(investment_instrument_id: md_instrument(name).id, status: "pending")
  action == "confirmed" ? s.confirm!(@user) : s.dismiss!(@user)
end

Then('a stock adjustment of {string} should exist for {string}') do |ratio, name|
  adj = StockAdjustment.find_by!(investment_instrument_id: md_instrument(name).id)
  expect(adj.adjustment.to_d).to eq(BigDecimal(ratio))
end

Then('no stock adjustment should exist for {string}') do |name|
  expect(StockAdjustment.where(investment_instrument_id: md_instrument(name).id)).to be_none
end

Given('there is another Market instrument {string} of the same company on NSE with ticker {string}') do |name, ticker|
  InvestmentInstrument.create!(entity: @user.entity, portfolio_company: @portfolio_company, name:, currency: "INR",
                               category: "Unlisted", sub_category: "Equity", sector: "Tech", ticker:, exchange: "NSE", pricing_method: "market")
end

When('I click Test feed on the Market Data settings') do
  visit(market_data_settings_path)
  click_on("Test feed")
end

Given('NSE reports these closes for the test-feed date:') do |table|
  step(%(NSE reports these closes for "#{MarketDataFeedRunner.latest_weekday.iso8601}":), table)
end

Then('{string} should have no market valuations') do |name|
  expect(Valuation.where(investment_instrument_id: md_instrument(name).id, source: "market")).to be_none
end

# ---------- Phase 6: derivatives ----------

def md_contract(name)
  DerivativeContract.find_by!(entity_id: @user.entity_id, name:)
end

Given('the fund {string} has derivatives switched on') do |fund_name|
  entity = @user.entity.reload
  entity.permissions.set(:enable_derivatives)
  entity.save!
  fund = md_fund(fund_name)
  fund.features.set(:enable_derivatives)
  fund.save!
end

Given('{string} has a derivative contract:') do |fund_name, table|
  fund = md_fund(fund_name)
  attrs = table.rows_hash.dup
  premium = attrs.delete("premium")
  instrument = attrs.delete("underlying_instrument")
  attrs["underlying_instrument_id"] = md_instrument(instrument).id if instrument
  hedge = attrs.delete("hedges")
  attrs["hedge_of"] = md_api(fund_name, hedge) if hedge
  notional = attrs.delete("notional")
  attrs["notional_cents"] = BigDecimal(notional) * 100 if notional
  %w[trade_date expiry_date].each { |k| attrs[k] = md_date(attrs[k]) if attrs[k] }
  attrs["listed"] = attrs["listed"] == "true" if attrs.key?("listed")
  @contract = DerivativeContract.new({ fund:, entity_id: fund.entity_id, currency: fund.currency, underlying_type: "instrument",
                                       settlement: "cash", listed: true }.merge(attrs.symbolize_keys))
  @contract_saved = DerivativeContractCreator.call(contract: @contract, premium:)
end

Then('the contract should be saved') do
  expect(@contract_saved).to be(true), @contract.errors.full_messages.join(", ")
end

Then('the contract should be refused with {string}') do |message|
  expect(@contract_saved).to be(false)
  expect(@contract.errors.full_messages.join(" | ")).to include(message)
end

Then('the contract {string} should be {word}') do |name, status|
  expect(md_contract(name).status).to eq(status)
end

Then('the contract {string} should have {string} open lots') do |name, lots|
  expect(md_contract(name).open_lots.to_d).to eq(BigDecimal(lots))
end

Then('the ledger should have a {string} entry of {string} for {string}') do |entry_name, amount, contract_name|
  contract = md_contract(contract_name)
  entries = AccountEntry.where(parent_type: "DerivativeEvent", parent_id: contract.derivative_events.select(:id), name: entry_name)
  expect(entries.pluck(:amount_cents).map { |a| a.to_d.round(2) }).to include(md_money_cents(amount).round(2))
end

Then('the ledger should have no {string} entry for {string}') do |entry_name, contract_name|
  contract = md_contract(contract_name)
  expect(AccountEntry.where(parent_type: "DerivativeEvent", parent_id: contract.derivative_events.select(:id), name: entry_name)).to be_none
end

When('the event {string} is recorded on {string} with key {string}') do |kv, name, key|
  attrs = kv.split(";").to_h { |pair| pair.split("=", 2) }
  params = { event_type: attrs["type"], event_date: md_date(attrs["date"]) }
  params[:lots] = BigDecimal(attrs["lots"]) if attrs["lots"]
  params[:amount_cents] = BigDecimal(attrs["amount"]) * 100 if attrs["amount"]
  params[:value_cents] = BigDecimal(attrs["value"]) * 100 if attrs["value"]
  params[:provider] = attrs["provider"] if attrs["provider"]
  params[:source] = attrs["source"] if attrs["source"]
  @event_result = DerivativeEventRecorder.call(contract: md_contract(name), idempotency_key: key, params:)
end

When('the event {string} is recorded on {string}') do |kv, name|
  step(%(the event "#{kv}" is recorded on "#{name}" with key "k-#{SecureRandom.hex(4)}"))
end

Then('the event should be refused with {string}') do |message|
  expect(@event_result.success?).to be(false)
  expect(@event_result.errors.join(" | ")).to include(message)
end

Then('the event should be recorded') do
  expect(@event_result.success?).to be(true), @event_result.errors.join(", ")
end

Then('{string} should have {int} {string} event(s)') do |name, count, type|
  expect(md_contract(name).derivative_events.where(event_type: type).count).to eq(count)
end

Then('the value of {string} on {string} should be {string}') do |name, date, value|
  expect(md_contract(name).value_on(md_date(date))).to eq(md_money_cents(value).round(2))
end

Then('the value of {string} in its fund on {string} should be {string}') do |name, date, value|
  contract = md_contract(name)
  totals = DerivativeContract.value_on(contract.fund, md_date(date))
  expect((totals[:assets_cents] - totals[:liabilities_cents]).round(2)).to eq(md_money_cents(value).round(2))
end

Then('{string} should hold {string} {string} bought at {string} each from the exercise') do |fund_name, qty, instrument_name, price|
  pi = md_fund(fund_name).portfolio_investments.joins(:investment_instrument).where(investment_instruments: { name: instrument_name })
                         .where("portfolio_investments.notes LIKE ?", "Exercise of%").buys.first
  expect(pi).not_to be_nil
  expect(pi.quantity.to_d).to eq(BigDecimal(qty))
  expect((pi.base_amount_cents.to_d / pi.quantity.to_d / 100).round(2)).to eq(BigDecimal(price))
end

Then('{string} should have sold {string} {string} at {string} each from the exercise') do |fund_name, qty, instrument_name, price|
  pi = md_fund(fund_name).portfolio_investments.joins(:investment_instrument).where(investment_instruments: { name: instrument_name })
                         .where("portfolio_investments.notes LIKE ?", "Exercise of%").sells.first
  expect(pi).not_to be_nil
  expect(pi.quantity.to_d).to eq(-BigDecimal(qty))
  expect((pi.base_amount_cents.to_d.abs / pi.quantity.to_d.abs / 100).round(2)).to eq(BigDecimal(price))
  expect(pi.reload.portfolio_attributions).to be_any
end

Then('{string} should have {int} holding(s) created by exercise') do |fund_name, count|
  expect(md_fund(fund_name).portfolio_investments.where("notes LIKE ?", "Exercise of%").count).to eq(count)
end

Given('NSE F&O reports a settlement price of {string} for {string} on {string}') do |price, symbol, date|
  md_webmock!
  rows = [{ sgmt: "FO", type: "IDO", ticker: "NIFTY", name: symbol, close: price, settle: price, lot: "75" }]
  stub_request(:get, NseFoProvider.new.url(md_date(date))).to_return(status: 200, body: md_zip("fo.csv", md_udiff_csv(rows)))
  stub_request(:get, NseEquityProvider.new.url(md_date(date))).to_return(status: 404, body: "")
  stub_request(:get, NseCorporateActionsProvider::HOME).to_return(status: 200, body: "")
  stub_request(:get, /#{Regexp.escape(NseCorporateActionsProvider::API)}/o).to_return(status: 200, body: "[]")
end

When('I open the holding {string} in {string}') do |instrument_name, fund_name|
  visit(aggregate_portfolio_investment_path(md_api(fund_name, instrument_name)))
end

When('I open the contract {string}') do |name|
  visit(derivative_contract_path(md_contract(name)))
end

When('I open the derivatives of {string}') do |fund_name|
  visit(fund_derivative_contracts_path(md_fund(fund_name)))
end

Then('the derivatives of {string} should be refused to {string}') do |fund_name, who|
  user = who == "the user" ? @user : User.find_by!(email: who)
  record = DerivativeContract.new(fund: md_fund(fund_name), entity_id: md_fund(fund_name).entity_id)
  expect(DerivativeContractPolicy.new(user, record).show?).to be(false)
end

Then('recording events on {string} should be refused to {string}') do |name, who|
  user = User.find_by!(email: who)
  expect(DerivativeContractPolicy.new(user, md_contract(name)).record_event?).to be(false)
end

Then('a user of another entity should be refused the contract {string}') do |name|
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Omar Capital #{rand(1000)}")
  omar = FactoryBot.create(:user, entity: other_entity)
  omar.add_role(:company_admin)
  expect(DerivativeContractPolicy.new(omar, md_contract(name)).show?).to be(false)
  expect(DerivativeContractPolicy::Scope.new(omar, DerivativeContract).resolve).not_to include(md_contract(name))
end

When('the expiry reminder job runs on {string}') do |date|
  DerivativeExpiryJob.perform_now(md_date(date).iso8601)
end

When('support turns off the entity derivatives feature') do
  e = @user.entity.reload
  e.permissions.unset(:enable_derivatives)
  e.save!
end

When('a derivative valuation upload row values {string} at {string} on {string} by {string}') do |name, value, date, by|
  contract = md_contract(name)
  upload = ImportUpload.new(entity: @user.entity, owner: contract.fund)
  upload.id = nil
  row = { "Contract" => name, "Valuation Date" => md_date(date).iso8601, "Value" => value, "Valued By" => by }
  ImportDerivativeEvent.new.save_row(row, upload, [], {})
end

Given('an employee {string} of the entity without fund access') do |email|
  u = FactoryBot.create(:user, entity: @user.entity, email:)
  u.add_role(:employee)
end

# ---------- Phase 7: OTC swaps ----------

Given('{string} has an agreement document {string}') do |fund_name, name|
  fund = md_fund(fund_name)
  @agreement = FactoryBot.create(:document, entity: fund.entity, owner: fund, name:, user: @user, folder: fund.document_folder || Folder.first)
end

Given('{string} has a swap {string} on {string} with the agreement') do |fund_name, name, notional|
  steps %(Given "#{fund_name}" has a derivative contract:
    | name                  | #{name}           |
    | contract_type         | irs               |
    | side                  | long              |
    | underlying_type       | rate              |
    | underlying_name       | MIBOR             |
    | notional              | #{notional}       |
    | trade_date            | 01 Jul 2026       |
    | expiry_date           | 30 Jun 2029       |
    | listed                | false             |
    | counterparty_name     | Bank X            |
    | agreement_document_id | #{@agreement.id}  |)
end
