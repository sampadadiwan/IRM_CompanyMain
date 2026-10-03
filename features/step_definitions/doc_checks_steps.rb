# Steps for Document Checks (features/core/doc_check_*.feature, kyc_doc_checks_journey.feature).
# The AI is replaced by DocChecks::FakeReader under @doc_checks_fake_ai.
# Worked examples in openspec/changes/document-checks/design.md#worked-examples

DOC_CHECKS_WORD_FILE = "public/sample_uploads/Contribution Agreement_Jan 2023.docx".freeze

# ── Setup ─────────────────────────────────────────────────────────────────────

Given("the entity requires the non-individual KYC documents {string}") do |names|
  @entity.entity_setting.update!(non_individual_kyc_doc_list: names)
end

# "dp=DP ID; client=Client ID" — text custom fields on the entity's IndividualKyc form
Given("the KYC form has the custom fields {string}") do |pairs|
  @kyc_form_type ||= FormType.find_or_create_by!(entity: @entity, name: "IndividualKyc") { |ft| ft.tag = "Default" }
  pairs.split(";").map(&:strip).each_with_index do |pair, index|
    name, label = pair.split("=", 2).map(&:strip)
    @kyc_form_type.form_custom_fields.find_or_create_by!(name:) do |fcf|
      fcf.label = label
      fcf.field_type = "TextField"
      fcf.position = index
    end
  end
end

Given("the KYC form's custom field {string} is deleted") do |name|
  FormCustomField.where(form_type: @entity.form_types, name:).find_each(&:destroy!)
end

# | document | action  | field     | look for          | tip | replace | expected |
Given("the entity has the document checks:") do |table|
  table.hashes.each_with_index do |row, index|
    DocCheck.create!(entity: @entity, record_type: "InvestorKyc", document_name: row["document"], action: row["action"],
                     field_name: row["field"].presence, look_for: row["look for"], tip: row["tip"].presence,
                     replace_existing: row["replace"] == "yes", expected_answer: row["expected"].presence || "yes",
                     position: index)
  end
end

# The design's shared setup: 11 checks on CML, PAN Card and Passport
Given("the entity has the sample document checks") do
  step "the entity has the document checks:", table(<<~TABLE)
    | document | action   | field               | look for                    | tip                    |
    | CML      | fill_in  | dp                  | DP ID                       | 8 chars, starts with IN |
    | CML      | fill_in  | client              | Client ID                   | 8 digits               |
    | CML      | fill_in  | address             | Address                     |                        |
    | CML      | fill_in  | bank_account_number | Bank account number         |                        |
    | CML      | fill_in  | ifsc_code           | IFSC code                   |                        |
    | CML      | compare  | PAN                 | PAN                         |                        |
    | CML      | compare  | full_name           | First holder name           |                        |
    | CML      | question |                     | Is it signed by the holder? |                        |
    | PAN Card | compare  | full_name           | Name                        |                        |
    | Passport | compare  | full_name           | Name                        |                        |
    | Passport | fill_in  | expiry_date         | Expiry date                 |                        |
  TABLE
end

Given("the check {string} on {string} has the tip {string}") do |look_for, document, tip|
  DocCheck.find_by!(entity: @entity, document_name: document, look_for:).update!(tip:)
end

# ── The AI's readings ─────────────────────────────────────────────────────────

# | document | look for | value |
Given("the AI reads:") do |table|
  table.hashes.group_by { |row| row["document"] }.each do |document, rows|
    existing = DocChecks::FakeReader.readings[document.downcase] || {}
    DocChecks::FakeReader.read(document, existing.merge(rows.to_h { |r| [r["look for"].downcase, r["value"]] }))
  end
end

# The design's default readings for Asha Rao's documents
Given("the AI reads the sample documents") do
  step "the AI reads:", table(<<~TABLE)
    | document | look for                    | value          |
    | CML      | DP ID                       | IN303622       |
    | CML      | Client ID                   | 86478611       |
    | CML      | Address                     | D109, MW       |
    | CML      | Bank account number         | 50100012345678 |
    | CML      | IFSC code                   | HDFC0000123    |
    | CML      | PAN                         | ABCPK1234F     |
    | CML      | First holder name           | ASHA RAO       |
    | CML      | Is it signed by the holder? | yes            |
    | PAN Card | Name                        | Asha Rao       |
    | Passport | Name                        | ASHA RAO       |
    | Passport | Expiry date                 | 2031-05-14     |
  TABLE
end

Given("the AI finds nothing for {string} on {string}") do |look_for, document|
  DocChecks::FakeReader.readings[document.downcase]&.delete(look_for.downcase)
end

Given("the AI service is down") do
  DocChecks::FakeReader.provider_error = true
end

Given("the AI gives an unreadable answer for {string}") do |document|
  DocChecks::FakeReader.garbage_documents << document.downcase
end

Then("the AI should have been called {int} times") do |count|
  expect(DocChecks::FakeReader.calls.size).to eq(count), "AI calls: #{DocChecks::FakeReader.calls.inspect}"
end

Then("the AI should have been sent the tip {string}") do |tip|
  expect(DocChecks::DocumentReader.prompt_for(DocCheck.where(entity: @entity).to_a)).to include("Tip: #{tip}")
end

# ── Documents ─────────────────────────────────────────────────────────────────

Given("the KYC's {string} document is a Word file") do |name|
  Document.where(owner_type: "InvestorKyc", owner_id: @investor_kyc.id, name:).find_each(&:destroy!)
  Document.create!(entity_id: @investor_kyc.entity_id, name:, owner: @investor_kyc, user: @user,
                   file: File.new(DOC_CHECKS_WORD_FILE, "r"))
end

Given("the entity no longer requires {string} from individuals") do |name|
  list = @entity.entity_setting.individual_kyc_doc_list.to_s.split(",").map(&:strip).reject { |n| n.casecmp?(name) }
  @entity.entity_setting.update!(individual_kyc_doc_list: list.join(", "))
end

Given("there is a non-individual KYC for the investor {string}") do |args|
  attrs = FactoryBot.attributes_for(:investor_kyc, verified: false, completed_by_investor: false).except(:submission_status, :verified, :completed_by_investor)
  kyc = NonIndividualKyc.new(attrs.merge(entity: @entity, investor: @investor, kyc_type: "non_individual", submission_status: "not_sent"))
  key_values(kyc, args)
  kyc.save!(validate: false)
  @investor_kyc = kyc.reload
end

# ── Running ───────────────────────────────────────────────────────────────────

When("documents are checked for the KYC") do
  @doc_check_error = nil
  DocChecks::StartRun.call(record: @investor_kyc.reload, user: @user)
  @investor_kyc.reload
rescue DocChecks::Error::AlreadyRunning => e
  @doc_check_error = e.message
end

Given("a document check is already running for the KYC") do
  DocCheckRun.create!(entity: @entity, record: @investor_kyc, user: @user, status: "running", started_at: Time.current)
end

# A run whose worker died an hour ago (card ④ Expiry)
Given("a document check for the KYC was left running an hour ago") do
  run = DocCheckRun.create!(entity: @entity, record: @investor_kyc, user: @user, status: "running", started_at: 1.hour.ago)
  run.update_columns(created_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
end

Then("the old document check should be expired") do
  expect(DocCheckRun.for_record(@investor_kyc).order(:id).first).to have_attributes(status: "could_not_run", error_message: "Timed out")
end

# Something a person saves while the run is still reading documents (the Fill in rule is re-checked)
Given("someone saves the KYC's {string} as {string} while the documents are being read") do |field_name, value|
  kyc_id = @investor_kyc.id
  entity = @entity
  DocChecks::FakeReader.during_read = lambda do
    kyc = InvestorKyc.find(kyc_id)
    DocChecks::Kyc.write(kyc, DocChecks::Kyc.field(entity, field_name), value)
    kyc.save!(validate: false)
  end
end

# A failure after the results are committed (here: the journey hook) must not cost the KYC its results
When("documents are checked for the KYC and the journey hook fails afterwards") do
  allow_any_instance_of(InvestorKyc).to receive(:journey_progress!).and_raise(RuntimeError, "journey down")
  expect { DocChecks::StartRun.call(record: @investor_kyc.reload, user: @user) }.to raise_error(RuntimeError, "journey down")
end

Then("the last document check should still be current") do
  run = latest_doc_check_run
  expect(run).to have_attributes(status: "done", current: true)
end

When("the {string} item is marked OK with {string}") do |item, reason|
  result = DocChecks::Assessment.new(@investor_kyc.reload).results.find { |r| r.look_for == item }
  result.mark_ok!(user: @user, reason:)
end

Then("the {string} item should still be marked OK with {string}") do |item, reason|
  result = DocChecks::Assessment.new(@investor_kyc.reload).results.find { |r| r.look_for == item }
  expect(result).to have_attributes(resolution: "marked_ok", resolve_reason: reason)
end

Then("the document check should be refused with {string}") do |message|
  expect(@doc_check_error).to eq(message)
  expect(DocCheckRun.for_record(@investor_kyc).count).to eq(1)
end

def latest_doc_check_run
  DocCheckRun.real.for_record(@investor_kyc).order(:id).last
end

Then("the last document check should be {string} with {int} OK and {int} needing attention") do |status, ok, attention|
  run = latest_doc_check_run
  expect(run.status).to eq(status), "error: #{run.error_message.inspect}"
  expect([run.ok_count, run.attention_count]).to eq([ok, attention]),
                                                 run.doc_check_results.map { |r| [r.document_name, r.look_for, r.outcome, r.doc_value] }.inspect
end

Then("the last document check couldn't run with {string}") do |reason|
  run = latest_doc_check_run
  expect(run.status).to eq("could_not_run")
  expect(run.error_message).to eq(reason)
end

# | document | item | outcome | note | document value | KYC value |   (blank cells are not checked)
Then("the KYC's document check results should include:") do |table|
  results = DocChecks::Assessment.new(@investor_kyc.reload).results
  table.hashes.each do |row|
    result = results.find { |r| r.document_name == row["document"] && (row["item"].blank? || r.look_for == row["item"]) }
    expect(result).to be_present, "No result for #{row['document']} / #{row['item']} in #{results.map { |r| [r.document_name, r.look_for, r.outcome] }}"
    expect(result.outcome).to eq(row["outcome"]), "#{row['document']} / #{row['item']}: #{result.attributes.slice('outcome', 'note', 'doc_value', 'record_value', 'explanation')}"
    expect(result.note).to eq(row["note"]) if row["note"].present?
    expect(result.doc_value).to eq(row["document value"]) if row["document value"].present?
    expect(result.record_value).to eq(row["KYC value"]) if row["KYC value"].present?
  end
end

Then("the KYC's document check results should have no {string} items") do |document|
  names = DocChecks::Assessment.new(@investor_kyc.reload).groups.map(&:name)
  expect(names).not_to include(document)
end

Then("the KYC's document check results should only cover {string}") do |documents|
  names = DocChecks::Assessment.new(@investor_kyc.reload).groups.map(&:name)
  expect(names).to eq(documents.split(",").map(&:strip))
end

Then("the KYC's {string} should be {string}") do |field_name, value|
  @investor_kyc.reload
  field = DocChecks::Kyc.field(@entity, field_name)
  expect(DocChecks::Kyc.read(@investor_kyc, field).to_s).to eq(value)
end

Then("the KYC's {string} should be empty") do |field_name|
  @investor_kyc.reload
  field = DocChecks::Kyc.field(@entity, field_name)
  expect(DocChecks::Kyc.read(@investor_kyc, field)).to be_blank
end

Then("the KYC's documents should be all valid") do
  expect(@investor_kyc.reload.all_docs_valid).to be(true)
end

Then("the KYC's documents should not be all valid") do
  expect(@investor_kyc.reload.all_docs_valid).to be(false)
end

Then("the KYC should still exist") do
  expect(InvestorKyc.exists?(@investor_kyc.id)).to be(true)
end

Then("the user gets a {string} alert {string}") do |level, message|
  alert = @captured_alerts.find { |a| a[:message] == message }
  expect(alert).to be_present, "Alerts: #{@captured_alerts.inspect}"
  expect(alert[:level]).to eq(level)
end

# ── The AI rules tool (AiDataManager#validate_document) ──────────────────────

When("an AI rule asks {string} about the KYC's {string} document") do |question, name|
  manager = AiDataManager.allocate
  manager.instance_variable_set(:@audit_log, {})
  manager.instance_variable_set(:@record, @investor_kyc)
  manager.instance_variable_set(:@document, Document.find_by!(owner: @investor_kyc, name:))
  @ai_rule_answer = manager.validate_document(question:)
end

Then("the AI rule should get the answer {string}") do |value|
  parsed = JSON.parse(@ai_rule_answer)
  expect(parsed.values.first["value"]).to eq(value)
end
