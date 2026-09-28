# Steps for features/fund/change_tracking_currency.feature (ChangeTrackingCurrencyJob and the
# support-only Change Tracking Currency screen). "the fund's tracking currency should be {string}" and
# "... should still be blank" come from fund_tracking_currency_lock_steps.rb; "I should see {string}"
# and "I click {string}" from features/common.rb.

# Each fund-currency column and the tracking column converted from it, per fund association - what
# TrackingCurrencyJob's convert_* methods write. Account entries are checked separately because
# "Percentage" entries are copied 1:1 rather than converted.
TRACKING_CONVERSIONS = {
  capital_remittance_payments: { amount_cents: :tracking_amount_cents },
  capital_remittances: { call_amount_cents: :tracking_call_amount_cents },
  capital_distribution_payments: { net_payable_cents: :tracking_net_payable_cents,
                                   gross_payable_cents: :tracking_gross_payable_cents },
  commitment_adjustments: { amount_cents: :tracking_amount_cents },
  capital_commitments: { orig_committed_amount_cents: :tracking_orig_committed_amount_cents }
}.freeze

# Sum of every stored tracking column of the fund, keyed "table.column" - a fingerprint that moves if
# any single tracking amount is rewritten.
def tracking_amount_fingerprint(fund)
  sums = TrackingCurrencyJob::TRACKING_COLUMNS.flat_map do |association, columns|
    columns.map { |column| ["#{association}.#{column}", fund.public_send(association).sum(column)] }
  end
  sums << ["account_entries.tracking_amount_cents", fund.account_entries.sum(:tracking_amount_cents)]
  pis = fund.portfolio_investments.include_proforma
  sums << ["portfolio_investments.tracking_amount_cents", pis.sum(:tracking_amount_cents)]
  sums << ["portfolio_investments.tracking_fmv_cents", pis.sum(:tracking_fmv_cents)]
  fund.reload
  TrackingCurrencyJob::FUND_TRACKING_COLUMNS.each { |column| sums << ["funds.#{column}", fund.public_send(column)] }
  sums.to_h
end

Given('fund ratios have been generated for the fund as of {string}') do |end_date|
  FundRatiosJob.perform_now(@fund.id, nil, Date.parse(end_date), @user.id, false)
  expect(@fund.fund_ratios.where(end_date: Date.parse(end_date))).to exist
end

Given('there is an exchange rate from {string} to {string} of {string} as of {string}') do |from, to, rate, as_of|
  ExchangeRate.create!(entity_id: @fund.entity_id, from:, to:, rate: BigDecimal(rate), as_of: Date.parse(as_of))
end

When("I open Change Tracking Currency from the fund's actions menu") do
  visit(fund_path(@fund))
  click_on("Actions")
  expect(page).to have_css('#misc_action_menu', visible: true)
  find('#misc_action_menu').hover
  click_on("Change Tracking Currency")
  expect(page).to have_current_path(change_tracking_currency_fund_path(@fund))
end

When('I visit the change tracking currency page for the fund') do
  visit(change_tracking_currency_fund_path(@fund))
end

# A blank currency picks the "None" option, which removes the tracking currency.
When('I submit a tracking currency change to {string} confirming with the fund name') do |currency|
  step %(I submit a tracking currency change to "#{currency}" confirming with "#{@fund.name}")
end

When('I submit a tracking currency change to {string} confirming with {string}') do |currency, confirmation|
  select(currency.presence || "None (remove the tracking currency)", from: "new_tracking_currency")
  fill_in("confirm_fund_name", with: confirmation)
  click_on("Change Tracking Currency")
end

# The test queue adapter is inline, so the job has already finished by the time the redirect lands.
Then('I should see the tracking currency change notice') do
  expect(page).to have_content("Tracking currency change to")
  expect(page).to have_current_path(fund_path(@fund))
end

# Claims the fund the way the controller does, then runs the job - for scenarios about the job
# itself rather than the screen. A job that raises is the "failed" scenario, so swallow it here and
# let the Then steps look at the state it left behind.
When('a tracking currency change to {string} is run for the fund') do |currency|
  expect(@fund.reload.claim_tracking_currency_change!(currency.presence)).to be(true)
  begin
    ChangeTrackingCurrencyJob.perform_now(@fund.id, @user.id, @fund.tracking_currency_change_token)
  rescue StandardError => e
    puts "ChangeTrackingCurrencyJob raised (expected in failure scenarios): #{e.message}"
  end
end

Given('a tracking currency change to {string} is pending on the fund') do |currency|
  expect(@fund.reload.claim_tracking_currency_change!(currency.presence)).to be(true)
end

Given('the tracking amount rebuild will fail once') do
  calls = 0
  allow_any_instance_of(TrackingCurrencyJob).to receive(:rebuild_fund).and_wrap_original do |original, *args|
    calls += 1
    raise "simulated failure part way through the rebuild" if calls == 1

    original.call(*args)
  end
end

# Simulates the job's worker dying mid-run: the claim stays "in_progress" with nothing to finish it.
Given('the pending tracking currency change started {string} hours ago') do |hours|
  @fund.reload.update_columns(tracking_currency_change_started_at: hours.to_i.hours.ago)
end

Given('the exchange rates from {string} to {string} are deleted') do |from, to|
  ExchangeRate.where(entity_id: @fund.entity_id, from:, to:).delete_all
end

# The Retry POST runs the whole rebuild inline before it redirects (jobs run inline in tests), which
# can outlast Capybara's default wait on a loaded machine - so wait for the redirect's notice longer.
When('I retry the tracking currency change from the fund page') do
  click_on "Retry"
  expect(page).to have_content("Tracking currency change restarted.", wait: 120)
end

When('I run the TrackingCurrencyJob with force for all funds in the entity') do
  TrackingCurrencyJob.new.perform(entity_id: @fund.entity_id, user_id: @user.id, force: true)
end

# Overwrite first, so a sweep that did process the fund would visibly rewrite them - a forced rebuild
# at unchanged rates would otherwise reproduce the same numbers and prove nothing.
Given('I know every tracking amount of the fund') do
  @fund.account_entries.update_all(tracking_amount_cents: 1)
  @tracking_fingerprint = tracking_amount_fingerprint(@fund)
end

Then('no tracking amount of the fund should have changed') do
  expect(tracking_amount_fingerprint(@fund)).to eq(@tracking_fingerprint)
end

Then('every tracking amount of the fund should be its fund amount at a rate of {string}') do |rate|
  rate = BigDecimal(rate)
  entries = @fund.account_entries
  converted = entries.where.not("name LIKE ?", "%Percentage%")
  expect(converted.where.not(amount_cents: 0)).to exist
  expect(converted.where("ABS(tracking_amount_cents - amount_cents * ?) > 0.01", rate)).not_to exist
  expect(entries.where("name LIKE ?", "%Percentage%").where("tracking_amount_cents <> amount_cents")).not_to exist

  TRACKING_CONVERSIONS.each do |association, pairs|
    pairs.each do |source, tracking|
      mismatched = @fund.public_send(association).where("ABS(#{tracking} - #{source} * ?) > 0.01", rate)
      expect(mismatched).not_to exist, "#{association}.#{tracking} is not #{source} x #{rate}"
    end
  end

  pis = @fund.portfolio_investments.include_proforma
  expect(pis.where("ABS(tracking_amount_cents - amount_cents * ?) > 0.01", rate)).not_to exist
end

# The convert_* methods write with update_all, which skips counter_culture; these rollups only
# match their rows because TrackingCurrencyJob#fix_tracking_rollups re-counts them.
Then("the fund's tracking rollups should match the rows they sum") do
  fund = @fund.reload
  expect(fund.tracking_call_amount_cents).to be_within(0.05).of(fund.capital_remittances.sum(:tracking_call_amount_cents))
  expect(fund.tracking_collected_amount_cents).to be_within(0.05).of(fund.capital_remittances.verified.sum(:tracking_collected_amount_cents))
  expect(fund.tracking_distribution_amount_cents).to be_within(0.05).of(fund.capital_distribution_payments.completed.sum(:tracking_net_payable_cents))
  expect(fund.tracking_committed_amount_cents).to be_positive
  expect(fund.tracking_committed_amount_cents).to be_within(0.05).of(fund.capital_commitments.sum(:tracking_committed_amount_cents))

  fund.capital_commitments.each do |cc|
    expect(cc.tracking_collected_amount_cents).to be_within(0.05).of(cc.capital_remittances.verified.sum(:tracking_collected_amount_cents))
    expect(cc.tracking_distribution_amount_cents).to be_within(0.05).of(cc.capital_distribution_payments.sum(:tracking_net_payable_cents))
  end
end

Then('every tracking amount of the fund should be zero') do
  nonzero = tracking_amount_fingerprint(@fund).reject { |_column, sum| sum.to_d.zero? }
  expect(nonzero).to be_empty
  # A sum can net to zero; make sure no single account entry still holds a value either.
  expect(@fund.account_entries.where.not(tracking_amount_cents: 0)).not_to exist
end

Then('the fund ratios should be labelled {string} and none {string}') do |current, old|
  expect(@fund.fund_ratios.where("name LIKE ?", "%#{current}%")).to exist
  step %(the fund ratios should not be labelled "#{old}")
end

Then('the fund ratios should not be labelled {string}') do |old|
  expect(@fund.fund_ratios.where("name LIKE ?", "%#{old}%")).not_to exist
end

Then('no tracking currency change should be pending on the fund') do
  @fund.reload
  expect(@fund.tracking_currency_change_state).to be_nil
  expect(@fund.tracking_currency_changing_to).to be_nil
end

Then('the tracking currency change should be marked failed') do
  expect(@fund.reload).to be_tracking_currency_change_failed
end

Then('the tracking currency change should be audited against the user') do
  audit = @fund.reload.audits.reorder(id: :desc).to_a.find { |a| a.audited_changes.key?("tracking_currency") }
  expect(audit).to be_present
  expect(audit.user_id).to eq(@user.id)
  expect(audit.audited_changes["tracking_currency"]).to eq(%w[USD EUR])
end

Then('an allocation run cannot be created for the fund') do
  run = AllocationRun.new(entity_id: @fund.entity_id, fund_id: @fund.id, user_id: @user.id,
                          start_date: Date.parse("2024-01-01"), end_date: Date.parse("2024-03-31"))
  expect(run).not_to be_valid
  expect(run.errors.full_messages.join).to include("tracking currency is being changed")
end
