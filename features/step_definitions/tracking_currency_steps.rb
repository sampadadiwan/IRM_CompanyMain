When('I run the TrackingCurrencyJob for the fund') do
  TrackingCurrencyJob.new.perform(fund_id: @fund.id, user_id: @user.id)
end

When('I run the TrackingCurrencyJob with force for the fund') do
  TrackingCurrencyJob.new.perform(fund_id: @fund.id, user_id: @user.id, force: true)
end

When('I run the TrackingCurrencyJob for all funds in the entity') do
  TrackingCurrencyJob.new.perform(entity_id: @user.entity.id, user_id: @user.id)
end

Given('the entity has {string} permission') do |permission|
  @user.entity.permissions.set(permission.to_sym)
  @user.entity.save!
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

  # Verify Distribution Payments — each tracking column should be populated whenever
  # its fund-currency source column is non-zero (all converted at the payment_date rate)
  cdps = @fund.capital_distribution_payments
  {
    net_payable_cents: :tracking_net_payable_cents,
    gross_payable_cents: :tracking_gross_payable_cents,
    reinvestment_with_fees_cents: :tracking_reinvestment_with_fees_cents,
    income_with_fees_cents: :tracking_income_with_fees_cents,
    expense_with_fees_cents: :tracking_expense_with_fees_cents,
    tax_with_fees_cents: :tracking_tax_with_fees_cents,
    display_only_with_fees_cents: :tracking_display_only_with_fees_cents
  }.each do |source, tracking|
    expect(cdps.where.not(tracking => 0).count).to be > 0 if cdps.where.not(source => 0).exists?
  end
end

Given('I trigger the tracking currency job again') do
  click_on("Actions")
  expect(page).to have_css('#misc_action_menu', visible: true)
  find('#misc_action_menu').hover
  expect(page).to have_button("Generate Tracking Numbers", visible: true)
  click_on("Generate Tracking Numbers")
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

# -----------------------------------------------------------------------
# Entity currency step definitions
# -----------------------------------------------------------------------

Then('the entity currency amounts should be calculated for the USD fund') do
  usd_fund = @user.entity.funds.find_by(currency: "USD")
  pis = usd_fund.portfolio_investments
  expect(pis.exists?).to be true

  pis_with_amount = pis.where.not(amount_cents: 0)
  expect(pis_with_amount.where.not(entity_currency_amount_cents: 0).count).to eq(pis_with_amount.count),
    "Expected all USD fund PIs with amount_cents to have entity_currency_amount_cents set"

  pis_with_amount.each do |pi|
    puts "PI #{pi.id}: amount_cents=#{pi.amount_cents} entity_currency_amount_cents=#{pi.entity_currency_amount_cents}"
    expect(pi.entity_currency_amount_cents).not_to eq(pi.amount_cents),
      "PI #{pi.id}: entity_currency_amount_cents should differ from amount_cents when fund.currency(USD) != entity.currency(INR)"
  end
end

Then('the entity currency FMV should be calculated for the USD fund') do
  usd_fund = @user.entity.funds.find_by(currency: "USD")
  pis_with_fmv = usd_fund.portfolio_investments.where.not(fmv_cents: 0)

  expect(pis_with_fmv.exists?).to be true

  pis_with_fmv.each do |pi|
    puts "PI #{pi.id}: fmv_cents=#{pi.fmv_cents} entity_currency_fmv_cents=#{pi.entity_currency_fmv_cents}"
    expect(pi.entity_currency_fmv_cents).not_to eq(0),
      "PI #{pi.id}: entity_currency_fmv_cents should be non-zero when fmv_cents is non-zero"
    expect(pi.entity_currency_fmv_cents).not_to eq(pi.fmv_cents),
      "PI #{pi.id}: entity_currency_fmv_cents should differ from fmv_cents when fund.currency(USD) != entity.currency(INR)"
  end
end

Then('the entity currency amounts should equal the fund currency amounts for the INR fund') do
  inr_fund = @user.entity.funds.find_by(currency: "INR")
  pis = inr_fund.portfolio_investments.where.not(amount_cents: 0)

  expect(pis.exists?).to be true

  pis.each do |pi|
    puts "PI #{pi.id}: amount_cents=#{pi.amount_cents} entity_currency_amount_cents=#{pi.entity_currency_amount_cents}"
    expect(pi.entity_currency_amount_cents).to eq(pi.amount_cents),
      "PI #{pi.id}: entity_currency_amount_cents should equal amount_cents when fund.currency(INR) == entity.currency(INR)"
  end
end

Given('I know the entity currency amounts for the fund') do
  @pi_entity_currency_amounts = @fund.portfolio_investments
                                     .where.not(entity_currency_amount_cents: 0)
                                     .pluck(:id, :entity_currency_amount_cents, :entity_currency_fmv_cents)
                                     .map { |id, amt, fmv| [id, { amount: amt, fmv: fmv }] }
                                     .to_h
end

Then('the entity currency amounts should not be recalculated for the fund') do
  @fund.portfolio_investments.where.not(entity_currency_amount_cents: 0).each do |pi|
    prior = @pi_entity_currency_amounts[pi.id]
    next unless prior

    puts "PI #{pi.id} amount: #{prior[:amount]} vs #{pi.entity_currency_amount_cents}"
    expect(pi.entity_currency_amount_cents).to eq(prior[:amount]),
      "PI #{pi.id}: entity_currency_amount_cents should be unchanged without force"
  end
end

Then('the entity currency amounts should be recalculated for the fund') do
  @fund.portfolio_investments.reload.where.not(entity_currency_amount_cents: 0).each do |pi|
    prior = @pi_entity_currency_amounts[pi.id]
    next unless prior && prior[:amount] != 0

    puts "PI #{pi.id} amount: #{prior[:amount]} vs #{pi.entity_currency_amount_cents}"
    expect(pi.entity_currency_amount_cents).not_to eq(prior[:amount]),
      "PI #{pi.id}: entity_currency_amount_cents should be recalculated after force with updated exchange rates"
  end
end

Then('every portfolio investment in the entity should have a non-zero entity currency amount') do
  entity = @user.entity
  pis_with_amount = entity.portfolio_investments.where.not(amount_cents: 0)

  expect(pis_with_amount.exists?).to be true

  pis_with_amount.each do |pi|
    puts "PI #{pi.id} (fund #{pi.fund_id}, #{pi.fund.currency}): entity_currency_amount_cents=#{pi.entity_currency_amount_cents}"
    expect(pi.entity_currency_amount_cents).not_to eq(0),
      "PI #{pi.id} in fund #{pi.fund.name} (#{pi.fund.currency}) should have entity_currency_amount_cents set for cross-fund aggregation"
  end

  total = entity.portfolio_investments.sum(:entity_currency_amount_cents)
  puts "Cross-fund total entity_currency_amount_cents = #{total}"
  expect(total).not_to eq(0)
end
