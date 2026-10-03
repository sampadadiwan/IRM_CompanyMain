# Steps for the KYC's Document checks tab, resolving items, the attention list and access
# (features/core/doc_check_results.feature, kyc_doc_checks_journey.feature).
# Worked examples H4–H6, H8, H9, H12, E19, X6–X8, X10 in openspec/changes/document-checks/design.md#worked-examples

def doc_check_item(item)
  find("#doc_checks_panel .doc-check-row[data-item='#{item}']")
end

When("I open the KYC's Document checks tab") do
  visit investor_kyc_path(@investor_kyc)
  find("#doc_checks_tab_link").click
  expect(page).to have_css("#doc_checks_panel")
end

Then("the Document checks tab title should be {string}") do |title|
  expect(page).to have_css("#doc_checks_tab_link", text: title, exact_text: true)
end

Then("the Document checks header should say {string}") do |text|
  expect(page).to have_css("#doc_checks_header", text:)
end

# | document | status | — each document's status where it is shown (needs your decision / missing / all good)
Then("the Document checks tab should show the documents:") do |table|
  table.hashes.each do |row|
    selector = "#doc_checks_panel [data-doc-check-document][data-document-name='#{row['document']}'] .doc-check-group-status"
    outcomes = -> { DocChecks::Assessment.new(@investor_kyc.reload).results.map { |r| [r.document_name, r.look_for, r.outcome, r.doc_value, r.record_value] } }
    expect(page).to have_css(selector, text: row["status"], visible: :all), -> { outcomes.call.inspect }
  end
end

# Page-level matchers re-query after the tab's frame is replaced (no stale element). Settled items may sit in
# the collapsed "All good" section, so hidden ones count too.
Then("the {string} item should say {string}") do |item, text|
  expect(page).to have_css("#doc_checks_panel .doc-check-row[data-item='#{item}'] .doc-check-sentence", text:, visible: :all)
end

Then("the {string} item should show {string}") do |item, text|
  expect(page).to have_css("#doc_checks_panel .doc-check-row[data-item='#{item}']", text:, visible: :all)
end

When("I use the document value for the {string} item, confirming {string}") do |item, confirm_text|
  # The app's Bootstrap confirm modal, not a browser dialog
  doc_check_item(item).find("button", text: "Use the document's").click
  within("#confirmModal") do
    expect(page).to have_css("#msg .action-summary__title", text: confirm_text)
    click_on("Proceed")
  end
  expect(page).to have_css("#doc_checks_panel .doc-check-row[data-item='#{item}'][data-resolution='used_document_value']", visible: :all)
end

# "Keep the KYC's …" (a mismatch) or "Mark as OK…" (anything else) opens the reason box
When("I mark the {string} item OK with {string}") do |item, reason|
  row = doc_check_item(item)
  row.find("details.doc-check-mark-ok summary").click
  row.fill_in("reason", with: reason)
  row.click_on("Mark as OK")
end

When("I undo the {string} item") do |item|
  find("#doc_checks_panel .doc-check-row[data-item='#{item}']", visible: :all).click_on("Undo")
end

Then("the {string} item should not offer to resolve it") do |item|
  row = doc_check_item(item)
  expect(row).to have_no_button(text: "Use the document's")
  expect(row).to have_no_css("details.doc-check-mark-ok")
end

# The shared Bootstrap confirm modal (#confirmModal) that Check documents opens
When("I click Check documents") do
  find("#doc_checks_check_btn").click
  expect(page).to have_css("#confirmModal.show")
end

Then("the confirmation should say {string}") do |text|
  expect(page).to have_css("#confirmModal #msg", text:)
end

When("I proceed") do
  within("#confirmModal") { click_on("Proceed") }
end

Then("a document check should have started for the KYC") do
  expect(page).to have_no_css("#confirmModal.show")
  # The tab is replaced once the run is queued; the run itself is on the record
  page.document.synchronize { raise Capybara::ExpectationNotMet, "no run yet" unless DocCheckRun.real.for_record(@investor_kyc).exists? }
end

Then("I should not be able to check documents") do
  expect(page).to have_no_button("Check documents")
end

# ── Trial (Try on a KYC) ──────────────────────────────────────────────────────

When("I try the checks on the KYC") do
  visit doc_checks_path
  find("#doc_check_try_record", visible: :all).select(@investor_kyc.to_s, visible: :all)
  click_on("doc_check_try_btn")
end

Then("the trial should say {string}") do |text|
  within("#doc_check_trial_panel") { expect(page).to have_content(text) }
end

Then("the KYC should have no current document check") do
  expect(DocCheckRun.for_record(@investor_kyc).where(current: true)).to be_empty
end

# ── Progress (H12) ────────────────────────────────────────────────────────────

Then("the documents should have been checked in the order {string}") do |list|
  shown = DocChecks::FakeReader.progress.map do |document, n, total|
    I18n.t("doc_checks.panel.checking", document:, n:, total:)
  end
  expected = list.split(",").map(&:strip).each_with_index.map do |document, index|
    I18n.t("doc_checks.panel.checking", document:, n: index + 1, total: list.split(",").size)
  end
  expect(shown).to eq(expected)
end

# ── Bulk and the attention list ───────────────────────────────────────────────

When("documents are checked in bulk for the KYCs {string}") do |names|
  ids = names.split(",").map(&:strip).map { |name| InvestorKyc.find_by!(entity: @entity, full_name: name).id }
  InvestorKycsBulkActionJob.perform_now(ids, @user.id, "ValidateDocsWithAi")
end

Given("there is a verified individual KYC for the investor {string}") do |args|
  step %(there is an individual KYC for the investor "#{args}")
  @investor_kyc.update_columns(verified: true, submission_status: "verified")
end

Then("the KYC {string} should have been checked") do |name|
  kyc = InvestorKyc.find_by!(entity: @entity, full_name: name)
  expect(DocCheckRun.real.for_record(kyc).where(status: "done")).to exist
end

Then("the KYC {string} should not have been checked") do |name|
  kyc = InvestorKyc.find_by!(entity: @entity, full_name: name)
  expect(DocCheckRun.for_record(kyc)).to be_empty
end

Given("the KYC {string} has the documents {string} and has been checked") do |name, documents|
  @investor_kyc = InvestorKyc.find_by!(entity: @entity, full_name: name)
  step %(the KYC has the documents "#{documents}")
  step "documents are checked for the KYC"
end

When("I open Documents needing attention") do
  visit doc_check_results_path
  expect(page).to have_css("h1", text: "Documents needing attention")
end

When("I filter the attention list by reason {string}") do |reason|
  within("#doc_check_results_filter") do
    select(reason, from: "reason")
    click_on("Filter")
  end
end

# Retried until it matches, so a list still reloading after a filter isn't read half-way
Then("the attention list should show the KYCs {string}") do |names|
  expected = names.split(",").map(&:strip)
  expect(page).to have_css("#doc_check_results_table")
  page.document.synchronize do
    shown = all("#doc_check_results_table tbody tr td:nth-child(2)").map(&:text).uniq
    raise Capybara::ExpectationNotMet, "attention list shows #{shown.inspect}, expected #{expected.inspect}" unless shown == expected
  end
end

When("I tick {string} and click Check again") do |name|
  row = find("#doc_check_results_table tbody tr", text: name, match: :first)
  row.find("input[type=checkbox]").check
  click_on("Check again (1)")
end

# Answers in the shape Doc Questions stored them (E20)
Given("the KYC has earlier AI answers for {string}") do |document|
  answers = { document => { "dp" => { "answer" => "IN303622", "explanation" => "The DP is IN303622", "question_type" => "Extraction" } } }
  @investor_kyc.update_columns(doc_question_answers: answers)
end

# ── Access (X6, X7, X10) ──────────────────────────────────────────────────────

Given("a fund admin {string} of another entity") do |name|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund")
  other.permissions.set(:enable_doc_llm_validation) if other.respond_to?(:permissions)
  other.save!
  @other_user = FactoryBot.create(:user, entity: other, first_name: name)
  @other_user.add_role(:company_admin)
end

Then("{string} can't see or resolve this entity's Document Checks") do |_name|
  user = @other_user
  expect(DocCheckPolicy::Scope.new(user, DocCheck).resolve.where(entity: @entity)).to be_empty
  expect(DocCheckResultPolicy::Scope.new(user, DocCheckResult).resolve.where(entity: @entity)).to be_empty
  result = DocCheckResult.where(entity: @entity).first
  expect(DocCheckResultPolicy.new(user, result).mark_ok?).to be(false) if result
  expect(DocCheckRunPolicy.new(user, @investor_kyc).panel?).to be(false)
end

Then("the investor user can't see the KYC's Document checks") do
  investor_user = @investor.investor_entity.employees.first
  expect(DocCheckRunPolicy.new(investor_user, @investor_kyc).panel?).to be(false)
  expect(DocChecks::Kyc.can_view?(investor_user, @investor_kyc)).to be(false)
end

Given("I can view but not edit the KYC") do
  allow_any_instance_of(InvestorKycPolicy).to receive(:update?).and_return(false)
end
