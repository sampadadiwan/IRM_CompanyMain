# frozen_string_literal: true

# Step definitions for features/core/kyc_doc_first_wizard.feature
# Tests the doc-first KYC wizard browser flow: upload docs → extraction → pre-filled edit form,
# both for company_admin (via new KYC) and for investors (via magic link to existing KYC).

# ── Background setup ──────────────────────────────────────────────────────────

# Creates a KycDocExtractorAgent with extraction rules for PAN (from "Upload Tax ID")
# and address (from "Upload Address Proof"). doc_label must match the document names
# that the _file.html.erb partial saves when files are uploaded via the browser form
# (document_name = field.label, which equals the name passed to file_fields).
# In the default APP_LOCALE "en": sys_t("investor_kyc.tax_id") = "Tax ID",
# so the upload field is "Upload Tax ID" and the saved document name is "Upload Tax ID".
Given('there is a KycDocExtractorAgent with PAN and address extraction rules for the entity') do
  # Create (or reuse) an InvestorKyc form type so extraction rules have a form_type_id key.
  @doc_wizard_form_type = FormType.where(entity: @entity, name: "InvestorKyc").first_or_create!(
    name: "InvestorKyc",
    tag:  "InvestorKyc"
  )

  @doc_extractor_agent = @entity.agents.find_or_initialize_by(agent_type: "KycDocExtractorAgent")
  @doc_extractor_agent.assign_attributes(
    enabled:   true,
    name:      "KYC Doc Extractor",
    llm_model: "gpt-4o",
    json_fields: {
      "overwrite_mode"   => "blank_only",
      "extraction_rules" => {
        @doc_wizard_form_type.id.to_s => [
          {
            "doc_label"    => "Upload Tax ID",
            "prompt"       => "Extract the tax identification number (PAN) from this document.",
            "target_field" => "PAN"
          },
          {
            "doc_label"    => "Upload Address Proof",
            "prompt"       => "Extract the full postal address from this document.",
            "target_field" => "address"
          }
        ]
      }
    }
  )
  @doc_extractor_agent.save!
  # Set the support_agents bitflag so entity.support_agents.kyc_doc_extractor_agent? returns true
  @entity.support_agents.set(:kyc_doc_extractor_agent)
  @entity.save!
end

# ── LLM stub ─────────────────────────────────────────────────────────────────

# Stubs LlmService so all LLM extract calls return the same plain string.
# KycDocExtractorAgent calls extract_plain_text(raw) which falls through to raw.to_s
# for non-RubyLLM::Message objects, so a plain string double works correctly.
# The stub is applied at the class level and is visible across threads (including
# the Puma server thread that handles the inline job in the test environment).
Given('the LLM will extract {string} from documents') do |value|
  fake_chat = double("llm_chat", ask: value)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
end

# ── Navigation (company admin) ────────────────────────────────────────────────

When('I visit the new investor KYC page') do
  visit new_investor_kyc_path
  sleep(1)
end



# ── Investor selection ────────────────────────────────────────────────────────

# The doc-first upload form shows a Select2 investor dropdown when investor_id is not
# pre-set. The new KYC form instantiates IndividualKyc by default, so the select element
# carries the "individual_kyc" prefix (individual_kyc_investor_id).
When('I select {string} as the investor for the KYC') do |investor_name|
  investor = Investor.find_by(investor_name: investor_name) ||
             Investor.where("investor_name ILIKE ?", "%#{investor_name}%").first
  expect(investor).not_to be_nil, "Investor '#{investor_name}' not found"
  select investor.investor_name, from: "individual_kyc_investor_id"
end

# ── File uploads via Uppy ─────────────────────────────────────────────────────

# Uppy's FileInput plugin renders a "Choose file" button/label inside the container div.
# Capybara's block form of attach_file intercepts the file chooser triggered by the click.
# After attaching, Uppy uploads the file to /upload (Shrine XHR endpoint on the test server)
# and on upload-success re-enables the submit button.
#
# Container div IDs derive from FormCustomField.to_name(field_name):
#   APP_LOCALE "en":    sys_t("investor_kyc.tax_id") = "PAN / Tax ID"
#     "Upload PAN / Tax ID" → upload_pan_tax_id → #custom_file_upload_pan_tax_id
#   APP_LOCALE "en-US": sys_t("investor_kyc.tax_id") = "Tax ID"
#     "Upload Tax ID"       → upload_tax_id     → #custom_file_upload_tax_id
#   "Upload Address Proof" → upload_address_proof → #custom_file_upload_address_proof

When('I upload {string} for the Tax ID document field') do |filename|
  filepath = File.absolute_path("./public/sample_uploads/#{filename}")
  page.attach_file(filepath) do
    within '#custom_file_upload_pan_tax_id' do
      click_on 'Choose file'
    end
  end
  # Wait for Uppy upload-success to re-enable the submit button before continuing.
  expect(page).to have_button('Continue to Fill Form →', disabled: false, wait: 15)
end

When('I upload {string} for the Address Proof document field') do |filename|
  filepath = File.absolute_path("./public/sample_uploads/#{filename}")
  page.attach_file(filepath) do
    within '#custom_file_upload_address_proof' do
      click_on 'Choose file'
    end
  end
  expect(page).to have_button('Continue to Fill Form →', disabled: false, wait: 15)
end

# ── Form submission (company admin) ──────────────────────────────────────────

# Clicks the submit button on the doc-first upload form.
# With the inline job adapter in test env, the extraction job runs synchronously:
#   1. KycDocExtractorJob executes → writes redirect URL to Redis (KycDocExtractorJob.redirect_key)
#   2. Controller redirects to processing_investor_kyc_path
#   3. Processing action consumes the marker → redirects immediately to edit page with doc_first_done=1
# The final page shows "Fields pre-filled from your documents".
When('I submit the doc-first upload form') do
  click_on 'Continue to Fill Form →'
  expect(page).to have_content('Fields pre-filled from your documents', wait: 20)
  @investor_kyc = InvestorKyc.order(:id).last
end

# ── Magic link navigation ─────────────────────────────────────────────────────

# The @investor_kyc instance variable must be set by a prior step
# (e.g. "there is a KYC for the investor with submission_status ...").
# Reuses the signed-link step from investor_kyc_send_workflow_steps.rb.

# ── Investor magic link: form submission ──────────────────────────────────────

# After uploading documents via the magic-link session, clicks the submit button
# on the doc_first_for_edit form (which POSTs to doc_first_upload PATCH route
# with the signed_id, then redirects through processing to the pre-filled edit page).
When('I submit the doc-first upload form via magic link') do
  click_on 'Continue to Fill Form →'
  expect(page).to have_content('Fields pre-filled from your documents', wait: 20)
end

# ── Cleanup ───────────────────────────────────────────────────────────────────

After('@doc_wizard_magic_link') do
  Capybara.session_name = :default
  Capybara.reset_sessions!
end
