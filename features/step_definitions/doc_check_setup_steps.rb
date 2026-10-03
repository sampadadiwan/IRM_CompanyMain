# Steps for Settings → Document Checks (features/core/doc_check_setup.feature): a tile per document, each
# document edited in its own side panel, suggested checks reviewed and added in one go.
# Worked examples H1, H2, E1–E5, E16, X4 in openspec/changes/document-checks/design.md#worked-examples

CHECK_SELECTOR = "[data-doc-check-page-target='row']".freeze

def doc_check_dom_id(document_name)
  ApplicationController.helpers.doc_check_card_dom_id(document_name)
end

def doc_check_tile(document_name)
  find("[data-doc-check-tile][data-document-name='#{document_name}']")
end

def doc_check_panel(document_name)
  find("##{doc_check_dom_id(document_name)}.show")
end

When("I open the Document Checks settings") do
  visit doc_checks_path
  expect(page).to have_css("h1", text: "Document Checks")
end

Then("I should see the documents {string}") do |names|
  shown = all("[data-doc-check-tile]").map { |tile| tile["data-document-name"] } # rubocop:disable Rails/Pluck -- Capybara nodes
  expect(shown).to eq(names.split(",").map(&:strip))
end

Then("the Document Checks page should say {string}") do |text|
  expect(page).to have_content(text)
end

When("I click {string} on the {string} tile") do |label, document_name|
  within(doc_check_tile(document_name)) { click_on(label) }
end

Then("the {string} tile should say {string}") do |document_name, text|
  expect(doc_check_tile(document_name)).to have_content(text)
end

# ── Suggested checks ──────────────────────────────────────────────────────────

When("I review the suggested checks") do
  click_on("Review & add")
  expect(page).to have_css("#doc_check_suggestions.show")
end

# | document | action | field | look for |
Then("the suggested checks should be:") do |table|
  shown = all("#doc_check_suggestions .doc-check-recommendation").flat_map do |block|
    block.all("label.form-check").map do |label|
      action = label.find(".badge").text.strip
      rest = label.find(".form-check-label").text.sub(action, "").strip
      field, look_for = rest.include?("←") ? rest.split("←").map(&:strip) : ["", rest]
      { "document" => block["data-document-name"], "action" => action, "field" => field, "look for" => look_for }
    end
  end
  expect(shown).to eq(table.hashes)
end

Then("the suggested checks should not list {string}") do |document_name|
  expect(page).to have_no_css("#doc_check_suggestions .doc-check-recommendation[data-document-name='#{document_name}']", visible: :all)
end

Then("the suggested checks should say {string}") do |text|
  within("#doc_check_suggestions") { expect(page).to have_content(text) }
end

When("I untick the suggested {string} on {string}") do |look_for, document_name|
  within("#doc_check_suggestions .doc-check-recommendation[data-document-name='#{document_name}']") do
    find("label.form-check", text: look_for).find("[data-role='pick']").uncheck
  end
end

# ── A document's side panel ───────────────────────────────────────────────────

When("I edit the {string} document") do |document_name|
  within(doc_check_tile(document_name)) { find("button[data-bs-toggle='offcanvas']").click }
  expect(page).to have_css("##{doc_check_dom_id(document_name)}.show")
end

KIND_BUTTONS = { "Fill in" => "Fill in a KYC field", "Compare" => "Compare with a KYC field",
                 "Yes-no question" => "Ask a yes-no question" }.freeze

When("I add a {string} check to the {string} document") do |kind, document_name|
  within(doc_check_panel(document_name)) { click_on(KIND_BUTTONS.fetch(kind)) }
end

When("I add a {string} check to the {string} document on the field {string}") do |kind, document_name, field_label|
  step %(I add a "#{kind}" check to the "#{document_name}" document)
  within(doc_check_panel(document_name)) { all(CHECK_SELECTOR).last.find("[data-role='field']").select(field_label) }
end

When("I change the last check's look for on the {string} document to {string}") do |document_name, text|
  within(doc_check_panel(document_name)) { all(CHECK_SELECTOR).last.find("[data-role='look-for']").fill_in(with: text) }
end

# Saved = back on the page with the confirmation (a refused save re-opens the panel with the row errors)
When("I save the {string} document") do |document_name|
  within(doc_check_panel(document_name)) { click_on("Save #{document_name}") }
  expect(page).to have_content("#{document_name}: checks saved"), -> { page.text.first(600) }
end

def doc_check_values(check)
  action = I18n.t("doc_checks.setup.actions.#{check.find("[data-role='action']", visible: :all).value}")
  field = check.all("[data-role='field']").first
  selected = field&.all("option", visible: :all)&.find(&:selected?)
  field_text = selected && selected.value.present? ? selected.text.sub(" (already used on this document)", "") : ""
  { "action" => action, "field" => field_text, "look for" => check.find("[data-role='look-for']").value }
end

# | action | field | look for |  — the document's checks in its panel
Then("the {string} document should have the checks:") do |document_name, table|
  within(doc_check_panel(document_name)) do
    expect(page).to have_css(CHECK_SELECTOR, count: table.hashes.size)
    expect(all(CHECK_SELECTOR).map { |check| doc_check_values(check) }).to eq(table.hashes)
  end
end

Then("the {string} document should say {string}") do |document_name, text|
  within(doc_check_panel(document_name)) { expect(page).to have_content(text) }
end

Then("the new check on the {string} document should show {string} greyed out") do |document_name, label|
  within(doc_check_panel(document_name)) do
    expect(all(CHECK_SELECTOR).last).to have_css("[data-role='field'] option[disabled]", text: label, visible: :all)
  end
end

Then("the entity should have {int} document checks on {string}") do |count, document_name|
  expect(DocCheck.where(entity: @entity, document_name:).count).to eq(count)
end

# | action | field | look for |  — what was saved
Then("the entity should have the document checks on {string}:") do |document_name, table|
  rows = DocCheck.where(entity: @entity, document_name:).ordered.map do |check|
    { "action" => check.action, "field" => check.field_name.to_s, "look for" => check.look_for }
  end
  expect(rows).to eq(table.hashes)
end

# ── Crafted requests (what the page itself never sends) ──────────────────────

# X4: the dropdown never offers the field
When("a request saves a Fill in check on {string} for the field {string}") do |document_name, field_name|
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:,
                                       rows: [{ "action" => "fill_in", "field_name" => field_name, "look_for" => field_name }])
  @card_saved = @card_form.save
end

# E3: the document as saved, plus one more check on an already-used field (the dropdown greys it out)
When("a request saves the {string} document with a second check on the field {string}") do |document_name, field_name|
  saved = DocCheck.where(entity: @entity, document_name:).ordered.map { |c| c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES) }
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:,
                                       rows: saved + [{ "action" => "fill_in", "field_name" => field_name, "look_for" => "#{field_name} again" }])
  @card_saved = @card_form.save
end

# The document as saved, with one check's look-for edited (the field left as it is)
When("a request saves the {string} document with the look for of {string} changed to {string}") do |document_name, from, to|
  rows = DocCheck.where(entity: @entity, document_name:).ordered.map do |c|
    attrs = c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES)
    attrs["look_for"] = to if c.look_for == from
    attrs
  end
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:, rows:)
  @card_saved = @card_form.save
  expect(@card_saved).to be(true), @card_form.rows.map { |r| r.errors.full_messages }.inspect
end

Then("the save should be refused with {string}") do |message|
  expect(@card_saved).to be(false)
  expect(@card_form.rows.flat_map { |r| r.errors[:field_name] }).to include(message)
end
