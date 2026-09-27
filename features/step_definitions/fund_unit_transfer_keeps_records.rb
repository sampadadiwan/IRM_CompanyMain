# Steps for features/fund/fund_unit_transfer_keeps_records.feature — a transfer must never delete
# (or soft-delete) the source commitment's remittances, payments, distribution payments or units.

# Live and soft-deleted counts of the records a transfer touches on one commitment.
def transfer_record_counts(commitment)
  remittance_ids = CapitalRemittance.with_deleted.where(capital_commitment_id: commitment.id).select(:id)
  {
    remittances: CapitalRemittance.where(capital_commitment_id: commitment.id).count,
    payments: CapitalRemittancePayment.where(capital_remittance_id: remittance_ids).count,
    distribution_payments: CapitalDistributionPayment.where(capital_commitment_id: commitment.id).count,
    fund_units: FundUnit.where(capital_commitment_id: commitment.id).count,
    deleted_remittances: CapitalRemittance.only_deleted.where(capital_commitment_id: commitment.id).count,
    deleted_payments: CapitalRemittancePayment.only_deleted.where(capital_remittance_id: remittance_ids).count,
    deleted_distribution_payments: CapitalDistributionPayment.only_deleted.where(capital_commitment_id: commitment.id).count,
    deleted_fund_units: FundUnit.only_deleted.where(capital_commitment_id: commitment.id).count
  }
end

Given("I note the records of the transfer's from and to commitments") do
  # Same commitments the 'fund units are transferred {string}' step picks
  @fund.reload
  @keep_from_cc = @fund.capital_commitments.first
  @keep_to_cc = @fund.capital_commitments.last
  @from_counts_before = transfer_record_counts(@keep_from_cc)
  @to_counts_before = transfer_record_counts(@keep_to_cc)
  puts "From #{@keep_from_cc.folio_id} before: #{@from_counts_before}"
  puts "To #{@keep_to_cc.folio_id} before: #{@to_counts_before}"
  expect(@from_counts_before[:remittances]).to be_positive
  expect(@from_counts_before[:fund_units]).to be_positive
end

Then('no record of the from commitment is deleted by the transfer') do
  expect(@from_cc.id).to eq(@keep_from_cc.id)
  after = transfer_record_counts(@keep_from_cc)
  puts "From #{@keep_from_cc.folio_id} after: #{after}"
  %i[remittances payments distribution_payments].each do |key|
    expect(after[key]).to eq(@from_counts_before[key]), "#{key}: #{@from_counts_before[key]} -> #{after[key]}"
  end
  %i[deleted_remittances deleted_payments deleted_distribution_payments deleted_fund_units].each do |key|
    expect(after[key]).to eq(@from_counts_before[key]), "#{key}: #{@from_counts_before[key]} -> #{after[key]}"
  end
end

Then('the from commitment gains exactly one fund unit') do
  after = transfer_record_counts(@keep_from_cc)
  expect(after[:fund_units]).to eq(@from_counts_before[:fund_units] + 1)
end

Then('the to commitment gains a copy of every from commitment remittance, payment and distribution payment') do
  expect(@to_cc.id).to eq(@keep_to_cc.id)
  after = transfer_record_counts(@keep_to_cc)
  puts "To #{@keep_to_cc.folio_id} after: #{after}"
  %i[remittances payments distribution_payments].each do |key|
    expect(after[key]).to eq(@to_counts_before[key] + @from_counts_before[key]), "#{key}: #{@to_counts_before[key]} + #{@from_counts_before[key]} -> #{after[key]}"
  end
  expect(after[:fund_units]).to eq(@to_counts_before[:fund_units] + 1)
end
