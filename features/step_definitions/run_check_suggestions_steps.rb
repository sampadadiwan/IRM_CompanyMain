# Step definitions for features/fund/run_check_suggestions.feature -- suggesting a fund's pre/post-run
# check formulas (AccountEntryAllocation::RunCheckSuggestions) and adding or exporting them.
#
# Suggestion sets are generated through FundFormulaOperation.start! (the controller's path), which the
# :inline ActiveJob adapter finishes before the next step. The LLM is always stubbed. Reuses the
# allocation run checks steps for uploads, folios and runs, and the incremental allocation UI steps for
# the signed-in session.

### Helpers ####################################################################

def rcs_operation
  @rcs_operation.reload
end

def rcs_suggestion!(helper)
  suggestion = rcs_operation.suggestion_list.find { |s| s.formula.start_with?(helper) }
  expect(suggestion).to be_present, "No suggestion calling #{helper}; got #{rcs_operation.suggestion_list.map(&:formula)}"
  suggestion
end

def rcs_generate!(ai: false)
  @rcs_operation = FundFormulaOperation.start!(fund: @fund, operation: "suggest_checks", user: @user, params: { "ai" => ai })
  expect(rcs_operation.status).to eq("previewed"), rcs_operation.error.to_s
end

### Setup ######################################################################

Given('the fund allocates entry type {string} by each upload\'s fund level UDR code') do |entry_type|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: entry_type, entry_type:, rule_for: "accounting", enabled: true,
                      rule_type: "AllocateAccountEntryIndividual-EntryType",
                      formula: 'custom_field_key = fund_account_entry.json_fields["fund_level_udr_code"]&.downcase.gsub("-","").parameterize(separator: "_"); ' \
                               "fund_account_entry.amount_cents * capital_commitment.json_fields[custom_field_key.to_s].to_d / 100")
end

Given('the fund reports the quarterly total of {string}') do |name|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: "Quarterly #{name}", entry_type: "Reporting", rule_for: "reporting",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: %(capital_commitment.quarterly(#{name.to_json},nil,@start_date,@end_date)))
end

Given('the fund stores the since-inception total of {string}') do |name|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: "Since Inception #{name}", entry_type: "Reporting", rule_for: "reporting",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: %(capital_commitment.since_inception(#{name.to_json},nil,@start_date,@end_date)))
end

Given('formula {string} is disabled') do |name|
  FundFormula.find_by!(fund_id: @fund.id, name:).update!(enabled: false)
end

Given('the fund has a formula {string} reading the unit setting {string}') do |name, key|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name:, entry_type: "Reporting", rule_for: "accounting", enabled: true,
                      rule_type: "GenerateAccountEntry", formula: %(capital_commitment.fund_unit_setting.json_fields[#{key.to_json}].to_d))
end

Given('every folio holds {string} percent of {string}') do |percent, folio_field|
  @arc_commitments.each_value { |cc| cc.update_column(:json_fields, cc.json_fields.to_h.merge(folio_field => percent)) }
end

Given('the AI suggests these checks:') do |table|
  reply = table.hashes.map { |row| row.merge("evidence" => []) }.to_json
  chat = double("chat")
  allow(LlmService).to receive(:ruby_llm_chat).and_return(chat)
  allow(chat).to receive(:ask).and_return(reply)
end

Given('the AI service is unavailable') do
  allow(LlmService).to receive(:ruby_llm_chat).and_raise(StandardError, "LLM unavailable")
end

### Generating #################################################################

When('support generates run check suggestions') do
  rcs_generate!
end

When('support generates run check suggestions with AI') do
  rcs_generate!(ai: true)
end

When('support adds the suggestion calling {string} as a {string}') do |helper, severity|
  suggestion = rcs_suggestion!(helper)
  @rcs_added = rcs_operation.add_suggestions!(keys: [suggestion.key], severities: { suggestion.key => severity }, user: @user)
end

When('support adds the suggestions calling {string} and {string}') do |first, second|
  keys = [rcs_suggestion!(first).key, rcs_suggestion!(second).key]
  @rcs_added = rcs_operation.add_suggestions!(keys:, user: @user)
end

When('support downloads the suggestions calling {string} and {string} and imports the file into the fund') do |first, second|
  keys = [rcs_suggestion!(first).key, rcs_suggestion!(second).key]
  @rcs_expected = rcs_operation.selected_suggestions(keys).map(&:formula_attributes)
  path = Rails.root.join("tmp/run_check_suggestions_#{@fund.id}.xlsx")
  File.binwrite(path, rcs_operation.suggestions_xlsx(keys:))
  upload = ImportUpload.create!(entity: @entity, owner: @fund, import_type: "FundFormula", name: "Run check suggestions",
                                user_id: @user.id, import_file: File.open(path))
  ImportUploadJob.perform_now(upload.id)
  @rcs_upload = upload.reload
ensure
  FileUtils.rm_f(path) if path
end

### Assertions ##################################################################

Then('a suggestion should call {string}') do |formula|
  expect(rcs_operation.suggestion_list.map(&:formula)).to include(formula)
end

Then('no suggestion should call {string}') do |helper|
  # not RSpec's all(...) matcher: in Cucumber `all` resolves to Capybara's page.all
  formulas = rcs_operation.suggestion_list.map(&:formula)
  expect(formulas.select { |f| f.start_with?(helper) }).to be_empty, formulas.inspect
end

Then('the suggestion calling {string} should cite formula {string}') do |helper, name|
  expect(rcs_suggestion!(helper).evidence.pluck("name")).to include(name)
end

# A fact about the data in the suggestion's evidence
Then('the suggestion calling {string} should note {string}') do |helper, text|
  expect(rcs_suggestion!(helper).evidence.pluck("detail").join(" ")).to include(text)
end

Then('the suggestion calling {string} should have been test-run against the run') do |helper|
  result = rcs_suggestion!(helper).result
  expect(result["result"]).not_to eq("not_tested"), result.inspect
  expect(result["run_id"]).to eq(@allocation_run.id)
end

Then('the add should be refused for {string} with {string}') do |name, reason|
  refusal = @rcs_added[:failed].find { |failed_name, _| failed_name == name }
  expect(refusal).to be_present, @rcs_added[:failed].inspect
  expect(refusal.last).to include(reason)
end

Then('the suggestion calling {string} should be marked already present') do |helper|
  suggestion = rcs_suggestion!(helper)
  expect(suggestion.already_present).to be_present
  expect(rcs_operation.addable?(suggestion)).to be(false)
end

Then('the suggestion calling {string} should have test result {string}') do |helper, result|
  expect(rcs_suggestion!(helper).result["result"]).to eq(result), rcs_suggestion!(helper).result.inspect
end

Then('the suggestion calling {string} should have test result {string} mentioning {string}') do |helper, result, text|
  suggestion = rcs_suggestion!(helper)
  expect(suggestion.result["result"]).to eq(result), suggestion.result.inspect
  expect(([suggestion.result["summary"]] + Array(suggestion.result["rows"]).flatten.map(&:to_s)).join(" ")).to include(text)
end

Then('generating the suggestions again should give the same formulas') do
  first = rcs_operation.suggestion_list.map(&:formula)
  second = AccountEntryAllocation::RunCheckSuggestions::Builder.new(@fund).suggestions.map(&:formula)
  expect(second).to eq(first)
end

Then('the fund should have a {string} check formula {string}') do |rule_type, formula|
  check = FundFormula.find_by(fund_id: @fund.id, rule_type:, formula:)
  expect(check).to be_present, "Checks: #{FundFormula.where(fund_id: @fund.id).run_checks.pluck(:formula)}"
  expect(check.enabled).to be(true)
  expect(check.rule_for).to eq("accounting")
  expect(check.description).to be_present
  expect(check.audits.where(action: "create")).to exist
end

Then('the added count should be {int}') do |count|
  expect(@rcs_added[:added].size).to eq(count), @rcs_added[:failed].inspect
end

Then('the import should create exactly those formulas') do
  expect(@rcs_upload.failed_row_count).to eq(0), @rcs_upload.status.to_s
  columns = %i[name description rule_type rule_for formula entry_type roll_up enabled tag_list generate_ytd_qtly meta_data add_to_commitment_cache]
  imported = FundFormula.where(fund_id: @fund.id, import_upload_id: @rcs_upload.id).order(:id).map { |f| f.slice(*columns).symbolize_keys }
  expect(imported).to eq(@rcs_expected.map { |attrs| attrs.slice(*columns) })
end

Then('a suggestion from AI should call {string}') do |formula|
  suggestion = rcs_operation.suggestion_list.find { |s| s.ai? && s.formula == formula }
  expect(suggestion).to be_present, rcs_operation.suggestion_list.map { |s| [s.source, s.formula] }.inspect
  expect(suggestion.result["result"]).to be_present
end

Then('the AI suggestion {string} should be rejected with {string}') do |name, text|
  rejected = Array(rcs_operation.plan["rejected"]).find { |r| r["name"] == name }
  expect(rejected).to be_present, rcs_operation.plan["rejected"].inspect
  expect(rejected["errors"].join(" ")).to include(text)
end

Then('the suggestion set should record the AI error {string}') do |text|
  expect(rcs_operation.plan["ai_error"]).to include(text)
  expect(rcs_operation.suggestion_list).not_to be_empty
end

When('the user opens Suggest run checks') do
  @session = iau_session_for(@user)
  @session.get "/fund_formula_operations/suggestions?fund_id=#{@fund.id}"
end

Then('the latest suggestion set should open') do
  expect(@session.response).to be_redirect
  expect(@session.response.location).to end_with("/fund_formula_operations/#{@rcs_operation.id}")
  @session.follow_redirect!
  expect(@session.response.status).to eq(200)
  expect(@session.response.body).to include("Generate again")
end
