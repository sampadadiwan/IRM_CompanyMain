When('I run the TrackingCurrencyJob for the fund') do
  TrackingCurrencyJob.new.perform(fund_id: @fund.id, user_id: @user.id)
end

Then('the tracking amounts should be calculated for the fund') do
  # Verify Account Entries
  expect(@fund.account_entries.count).to be > 0
  non_percentage_entries = @fund.account_entries.where.not("name LIKE ?", "%Percentage%")
  expect(non_percentage_entries.where.not(tracking_amount_cents: 0).count).to be > 0 if non_percentage_entries.where.not(amount_cents: 0).exists?

  # Verify Capital Commitments
  expect(@fund.capital_commitments.count).to be > 0
  expect(@fund.capital_commitments.where.not(tracking_committed_amount_cents: 0).count).to be > 0

  # Verify Remittance Payments
  expect(@fund.capital_remittance_payments.where.not(tracking_amount_cents: 0).count).to be > 0 if @fund.capital_remittance_payments.exists?

  # Verify Portfolio Investments
  expect(@fund.portfolio_investments.where.not(tracking_amount_cents: 0).count).to be > 0 if @fund.portfolio_investments.exists?
end
