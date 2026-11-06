# Fund pack setup and maker–checker steps — business-rules.md (groups 2, 10, 11)

When('{string} attaches {string} to {string} as {string}') do |_user, pack_name, fund_name, classification|
  @attach = FundCompliancePack.new(entity_id: horizon.id, fund: cmp_fund(fund_name), compliance_pack: CompliancePack.find_by!(name: pack_name),
                                   classification:)
  @attached = @attach.save
end

When('{string} attaches {string} to {string} without a classification') do |_user, pack_name, fund_name|
  fund = cmp_fund(fund_name)
  pack = CompliancePack.find_by!(name: pack_name)
  version = pack.version_for_new_attachment(fund)
  prefill = version.classifications.include?(fund.category) ? fund.category : nil
  @attach = FundCompliancePack.new(entity_id: horizon.id, fund:, compliance_pack: pack, classification: prefill)
  @attached = @attach.save
end

When('{string} attaches {string} to {string} twice') do |user, pack_name, fund_name|
  2.times { step %("#{user}" attaches "#{pack_name}" to "#{fund_name}" without a classification) }
end

Then('{string} carries {string} once') do |fund_name, pack_name|
  expect(FundCompliancePack.joins(:compliance_pack).where(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: pack_name }).count).to eq(1)
end

Then('attaching is refused with {string}') do |message|
  expect(@attached).to be false
  expect(@attach.errors.full_messages.join("\n")).to include(message)
end

Given('{string} has no SEBI attachment') do |fund_name|
  FundCompliancePack.joins(:compliance_pack).where(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: "SEBI — AIF" }).delete_all
end

Given('{string} has the Category {string}') do |fund_name, category|
  cmp_fund(fund_name).update_column(:category, category)
end

Given('{string} carries {string} as {string}') do |fund_name, pack_name, classification|
  cmp_attach!(cmp_fund(fund_name), CompliancePack.find_by!(name: pack_name), classification)
end

Then('the setup grid shows {string} with {string} as {string}') do |fund_name, pack_name, label|
  fp = FundCompliancePack.joins(:compliance_pack).find_by!(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: pack_name })
  expect(fp.classification.presence || "⚠ choose").to eq(label)
end

When('{string} requests an override of {string} on {string} to {int} because {string}') do |user, check, fund_name, value, reason|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "override", target: cmp_fund_pack(fund_name),
                                         check_key: cmp_check_key(check, fund_name), reason:, payload: { "limit" => value })
end

When('{string} requests to disable {string} on {string} because {string}') do |user, check, fund_name, reason|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "disable", target: cmp_fund_pack(fund_name),
                                         check_key: cmp_check_key(check, fund_name), reason:)
end

When('{string} requests to detach {string} from {string} because {string}') do |user, pack_name, fund_name, reason|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "detach", target: cmp_fund_pack(fund_name, pack_name), reason:)
end

Then('the request was accepted') do
  expect(@submit.error).to be_nil
end

Then('the compliance request is refused with {string}') do |message|
  expect(@submit.error.to_s).to include(message)
end

When('{string} approves the latest request') do |user|
  @decision = ComplianceRequestDecide.call(request: ComplianceRequest.order(:id).last, decider: cmp_user(user), decision: "approve")
end

When('{string} rejects the latest request') do |user|
  @decision = ComplianceRequestDecide.call(request: ComplianceRequest.order(:id).last, decider: cmp_user(user), decision: "reject")
end

Then('the latest request is labelled {string}') do |label|
  expect(ComplianceRequest.order(:id).last.approval_label).to eq(label)
end

Then('the override is not in force on {string}') do |fund_name|
  expect(cmp_fund_pack(fund_name).active_overrides).to be_empty
end

Then('{string} has no {string} result') do |fund_name, check|
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  expect(ComplianceResult.where(fund_compliance_pack_id: fp_ids, check_key: cmp_check_key(check, fund_name))).to be_none
end

Given('monitoring is off for Horizon') do
  cmp_setup.update!(monitoring_enabled: false)
end

Then('monitoring is still off for Horizon') do
  expect(cmp_setup.reload.monitoring_enabled).to be false
end

When('{string} turns monitoring on') do |user|
  @setup_result = ComplianceSetupUpdate.call(setup: cmp_setup, params: ActionController::Parameters.new(monitoring_enabled: "1").permit!, user: cmp_user(user))
end

Then('the setup says {string}') do |text|
  expect(@setup_result.notice.to_s + @setup_result.error.to_s).to include(text)
end

When('{string} saves the IC members {string} with quorum {int}') do |user, names, quorum|
  entries = names.split(",").map { |n| { "name" => n.strip } }
  params = ActionController::Parameters.new(reference_lists: { "ic_members" => { "quorum" => quorum.to_s, "entries" => entries } }).permit!
  @setup_result = ComplianceSetupUpdate.call(setup: cmp_setup, params:, user: cmp_user(user))
end

Then('the setup saves') do
  expect(@setup_result.error).to be_nil
end

Then('the setup is refused with {string}') do |message|
  expect(@setup_result.error.to_s).to include(message)
end

Then('{string} is a compliance viewer, editor and approver') do |user|
  u = cmp_user(user)
  expect([ComplianceAccess.viewer?(u), ComplianceAccess.editor?(u), ComplianceAccess.approver?(u)]).to eq([true, true, true])
end

Then('the Compliance home lists {string} as {string}') do |fund_name, label|
  monitored = FundCompliancePack.active.exists?(fund_id: cmp_fund(fund_name).id)
  expect(monitored ? "Monitored" : "Not monitored").to eq(label)
end

Then('the {string} {string} result shows the setup {string} with limit {int}') do |date, check, override, limit|
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund("Horizon Growth Fund I").id).select(:id)
  result = ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fp_ids, check_key: cmp_check_key(check),
                                                         compliance_runs: { run_date: cmp_date(date) }).last
  setup = ComplianceSetupAsOf.call(result)
  expect(setup["override"]).to eq(override)
  expect(setup["limit"].to_d).to eq(limit.to_d)
end
