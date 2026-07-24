Then('the aml status override should be recorded in the audit trail with comment {string}') do |comment|
  kyc = InvestorKyc.last
  audit = kyc.audits.where("audited_changes LIKE ?", "%aml_status%").last
  expect(audit).not_to be_nil
  expect(audit.comment).to eq(comment)
end
