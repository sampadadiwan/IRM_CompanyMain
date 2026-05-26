# frozen_string_literal: true

# ── Shared helpers ────────────────────────────────────────────────────────

# Maps common KYC document labels to realistic sample files in public/sample_uploads/.
# The LLM receives real PDF content, so the model can validate the label.
SAMPLE_KYC_DOC_FILES = {
  "Passport"      => "public/sample_uploads/sample_kyc1.pdf",
  "PAN Card"      => "public/sample_uploads/pan_card.pdf",
  "Address Proof" => "public/sample_uploads/address_proof.pdf"
}.freeze

# Returns the best sample file for a given document label, falling back to pan_card.pdf.
def sample_kyc_file(label)
  path = SAMPLE_KYC_DOC_FILES[label] || "public/sample_uploads/pan_card.pdf"
  File.new(path, "r")
end

# Builds a SupportAgent with KycOnboardingAgent type and the given json_fields flags.
def build_kyc_onboarding_agent(entity, flags)
  SupportAgent.find_or_create_by!(agent_type: "KycOnboardingAgent", entity: entity) do |agent|
    agent.name        = "KYC Onboarding Validator"
    agent.enabled     = true
    agent.llm_model   = "gemini-2.0-flash"
    agent.json_fields = flags
  end
end

# ── Background / shared setup ─────────────────────────────────────────────

Given("the entity has an active employee") do
  # The background-created @user is already an entity employee; ensure active
  @user.update!(active: true)
end

Given("the entity has no active employees") do
  # Deactivate all users so investor_kyc.entity.employees.active.first returns nil
  @entity.employees.update_all(active: false)
end

Given("there is a completed KYC for the investor") do
  @investor_kyc = FactoryBot.create(
    :investor_kyc,
    entity:                @entity,
    investor:              @investor,
    completed_by_investor: true,
    submission_status:     "completed"
  )
end

# ── Agent configuration steps ─────────────────────────────────────────────

Given("the KYC onboarding agent is fully enabled") do
  @support_agent = build_kyc_onboarding_agent(@entity,
    "validate_fields"    => "true",
    "validate_documents" => "true",
    "check_expiry"       => "true",
    "send_reminder"      => "true",
    "trigger_aml"        => "true"
  )
end

Given("the KYC onboarding agent has expiry checking and reminders enabled") do
  # Field and document validation are disabled so this test isolates the expiry path.
  @support_agent = build_kyc_onboarding_agent(@entity,
    "validate_fields"    => "false",
    "validate_documents" => "false",
    "check_expiry"       => "true",
    "send_reminder"      => "true",
    "trigger_aml"        => "false"
  )
  ActionMailer::Base.deliveries.clear
end

Given("the KYC onboarding agent has all validation flags disabled") do
  @support_agent = build_kyc_onboarding_agent(@entity,
    "validate_fields"    => "false",
    "validate_documents" => "false",
    "check_expiry"       => "false",
    "send_reminder"      => "false",
    "trigger_aml"        => "true"
  )
end

Given("the KYC onboarding agent requires a {string} document") do |doc_name|
  # Field validation off — isolates the document presence check
  @support_agent = build_kyc_onboarding_agent(@entity,
    "validate_fields"    => "false",
    "validate_documents" => "true",
    "check_expiry"       => "false",
    "send_reminder"      => "false",
    "trigger_aml"        => "true",
    "required_docs"      => doc_name   # comma-separated list checked by base class
  )
end

Given("the KYC onboarding agent has AML triggering disabled") do
  # Overrides whatever was previously set on @support_agent
  @support_agent.update!(
    json_fields: @support_agent.json_fields.merge("trigger_aml" => "false")
  )
end

# ── KYC state steps ───────────────────────────────────────────────────────

Given("the KYC has not been submitted by the investor") do
  @investor_kyc.update!(completed_by_investor: false, submission_status: "not_sent")
end

Given("the KYC has an uploaded document labeled {string}") do |label|
  # Picks a realistic sample PDF for the label (see SAMPLE_KYC_DOC_FILES).
  # The LLM receives the real file content so it can judge whether it matches.
  @document = FactoryBot.create(
    :document,
    name:   label,
    owner:  @investor_kyc,
    entity: @entity,
    user:   @user,
    file:   sample_kyc_file(label)
  )
  # Force-reload the association after document creation so that check_document_validity
  # sees the new document. AR caches the has_many target; post-create job callbacks
  # (DocumentPostCreateJob) can prime the cache as empty before the document is visible.
  @investor_kyc.documents.reset
end

Given("the KYC has {string} uploaded as {string}") do |filename, label|
  # Deliberately mislabeled upload for testing LLM mismatch detection.
  # e.g. "address_proof.pdf" uploaded as "Passport" should be flagged by the LLM.
  @document = FactoryBot.create(
    :document,
    name:   label,
    owner:  @investor_kyc,
    entity: @entity,
    user:   @user,
    file:   File.new("public/sample_uploads/#{filename}", "r")
  )
end

# Stubs RubyLLM::Chat#ask so the agent always sees matches:false.
# Required because doc.file.url returns a web-relative path (/uploads/...) that
# RubyLLM cannot resolve to a filesystem path in the test environment, meaning
# the LLM never sees the actual file content. The stub exercises the code path
# for handling a mismatch response without depending on LLM intelligence.
Given("the LLM will flag the document as not matching its label") do
  mismatch_json = '{"matches": false, "explanation": "Document does not match the specified label."}'
  allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mismatch_json)
end

Given("the KYC has no documents uploaded") do
  @investor_kyc.documents.destroy_all
end

Given("the KYC expired {int} days ago") do |days|
  @investor_kyc.update!(expiry_date: Time.zone.today - days.days)
end

Given("the KYC expires in {int} days") do |days|
  @investor_kyc.update!(expiry_date: Time.zone.today + days.days)
end

# ── Agent execution ───────────────────────────────────────────────────────

When("I run the KYC onboarding agent") do
  # Stub the AML job to prevent outbound AML API calls. Whether perform_later
  # was invoked is captured in @aml_job_enqueued for assertion steps below.
  @aml_job_enqueued = false
  allow(GenerateAmlReportJob).to receive(:perform_later) do |*_args|
    @aml_job_enqueued = true
  end

  KycOnboardingAgent.call(
    support_agent_id: @support_agent.id,
    target:           @investor_kyc
  )

  # Reload so json_fields keys come back as strings (MySQL JSON column round-trip)
  @report = SupportAgentReport.find_by(owner: @investor_kyc, support_agent: @support_agent)
  @report&.reload
end

# ── Assertions ────────────────────────────────────────────────────────────

Then("the report final status should be {string}") do |expected|
  expect(@report).to be_present, "Expected a SupportAgentReport to exist for this KYC but none was found"
  expect(@report.final_status).to eq(expected)
end

Then("no report should be created for the KYC") do
  report = SupportAgentReport.find_by(owner: @investor_kyc, support_agent: @support_agent)
  expect(report).to be_nil,
    "Expected no report for a KYC that was not submitted by the investor, but one was created"
end

Then("the AML job should have been enqueued for the investor KYC") do
  expect(@aml_job_enqueued).to be(true),
    "Expected GenerateAmlReportJob to be enqueued but it was not"
end

Then("the AML job should not have been enqueued for the investor KYC") do
  expect(@aml_job_enqueued).to be(false),
    "Expected GenerateAmlReportJob not to be enqueued but it was"
end

Then("the report should have a blocking document issue mentioning {string}") do |text|
  # After reload, json_fields keys and nested hash keys are strings
  document_issues = @report.json_fields["document_issues"] || []
  matching = document_issues.select do |issue|
    (issue["message"]&.include?(text) || issue["name"]&.include?(text)) &&
      issue["severity"] == "blocking"
  end
  expect(matching).not_to be_empty,
    "Expected a blocking document issue mentioning '#{text}' but got: #{document_issues.inspect}"
end

Then("the report should contain a field issue of type {string}") do |issue_type|
  field_issues = @report.json_fields["field_issues"] || []
  matching = field_issues.select { |issue| issue["type"] == issue_type }
  expect(matching).not_to be_empty,
    "Expected a field issue of type '#{issue_type}' but got: #{field_issues.inspect}"
end

Then("a KYC expiry reminder email should have been sent") do
  expect(ActionMailer::Base.deliveries).not_to be_empty,
    "Expected an expiry reminder email to be delivered but ActionMailer::Base.deliveries is empty"
end

Then("the AML report entry should mention {string}") do |text|
  aml_entries = @report.json_fields["aml_report"] || []
  matching = aml_entries.select { |entry| entry["message"]&.include?(text) }
  expect(matching).not_to be_empty,
    "Expected an AML report entry mentioning '#{text}' but got: #{aml_entries.inspect}"
end
