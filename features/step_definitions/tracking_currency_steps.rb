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

Given('I trigger the tracking currency job again') do
  click_on("Actions")
  expect(page).to have_css('#misc_action_menu', visible: true)
  find('#misc_action_menu').hover
  expect(page).to have_button("Generate Tracking Numbers", visible: true)
  click_on("Generate Tracking Numbers")
  sleep(3)
end

Given('I know the amounts calculated for the fund') do
  @account_entry_tracking_amounts = @fund.account_entries.where.not("name LIKE ?", "%Percentage%").pluck(:id, :tracking_amount_cents).to_h
  @capital_commitment_tracking_amounts = @fund.capital_commitments.where.not(tracking_committed_amount_cents: 0).pluck(:id, :tracking_committed_amount_cents).to_h
  @capital_remittance_payment_tracking_amounts = @fund.capital_remittance_payments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h
  @portfolio_investment_tracking_amounts = @fund.portfolio_investments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h
end


Then('the tracking amounts should not be recalculated') do
  @account_entry_tracking_amounts_1 = @fund.account_entries.where.not("name LIKE ?", "%Percentage%").pluck(:id, :tracking_amount_cents).to_h
  @capital_commitment_tracking_amounts_1 = @fund.capital_commitments.where.not(tracking_committed_amount_cents: 0).pluck(:id, :tracking_committed_amount_cents).to_h
  @capital_remittance_payment_tracking_amounts_1 = @fund.capital_remittance_payments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h
  @portfolio_investment_tracking_amounts_1 = @fund.portfolio_investments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h

  puts "Checking AE amounts UNCHANGED"
  @account_entry_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@account_entry_tracking_amounts_1[id]}"
    expect(@account_entry_tracking_amounts_1[id]).to eq(amount)
  end

  puts "Checking Commitments amounts UNCHANGED"
  @capital_commitment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@capital_commitment_tracking_amounts_1[id]}"
    expect(@capital_commitment_tracking_amounts_1[id]).to eq(amount)
  end

  puts "Checking Remittance Payments amounts UNCHANGED"
  @capital_remittance_payment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@capital_remittance_payment_tracking_amounts_1[id]}"
    expect(@capital_remittance_payment_tracking_amounts_1[id]).to eq(amount)
  end

  puts "Checking Portfolio Investments amounts UNCHANGED"
  @portfolio_investment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@portfolio_investment_tracking_amounts_1[id]}"
    expect(@portfolio_investment_tracking_amounts_1[id]).to eq(amount)
  end
end

Given('I update all the exchange rates') do
  @fund.entity.exchange_rates.each do |er|
    new_rate = er.rate + er.rate * 0.5
    puts "#{er.id}: #{er.rate} -> #{new_rate}"
    er.update_columns(rate: new_rate)
  end
end

Given('I trigger the tracking currency job again with force regeneration') do
  click_on("Actions")
  find('#misc_action_menu').hover
  click_on("Generate Tracking Numbers (Force Regeneration)")
  sleep(3)
end

Then('the tracking amounts should be recalculated') do
  @account_entry_tracking_amounts_2 = @fund.account_entries.where.not("name LIKE ?", "%Percentage%").pluck(:id, :tracking_amount_cents).to_h
  @capital_commitment_tracking_amounts_2 = @fund.capital_commitments.where.not(tracking_committed_amount_cents: 0).pluck(:id, :tracking_committed_amount_cents).to_h
  @capital_remittance_payment_tracking_amounts_2 = @fund.capital_remittance_payments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h
  @portfolio_investment_tracking_amounts_2 = @fund.portfolio_investments.where.not(tracking_amount_cents: 0).pluck(:id, :tracking_amount_cents).to_h

  puts "Checking AE amounts CHANGED!"
  @account_entry_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@account_entry_tracking_amounts_2[id]}"
    expect(@account_entry_tracking_amounts_2[id]).not_to eq(amount)
  end

  puts "Checking Commitments amounts CHANGED!"
  @capital_commitment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@capital_commitment_tracking_amounts_2[id]}"
    expect(@capital_commitment_tracking_amounts_2[id]).not_to eq(amount)
  end

  puts "Checking Remittance Payments amounts CHANGED!"
  @capital_remittance_payment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@capital_remittance_payment_tracking_amounts_2[id]}"
    expect(@capital_remittance_payment_tracking_amounts_2[id]).not_to eq(amount)
  end

  puts "Checking Portfolio Investments amounts CHANGED!"
  @portfolio_investment_tracking_amounts.each do |id, amount|
    puts "#{id} - #{amount} vs #{@portfolio_investment_tracking_amounts_2[id]}"
    expect(@portfolio_investment_tracking_amounts_2[id]).not_to eq(amount)
  end
end
