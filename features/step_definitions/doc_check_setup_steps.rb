# Steps for Settings → Document Checks (features/core/doc_check_setup.feature).
# Worked examples H1, H2, E1–E5, E16, X4 in openspec/changes/document-checks/design.md#worked-examples

def doc_check_card(document_name)
  find("##{ApplicationController.helpers.doc_check_card_dom_id(document_name)}")
end

When("I open the Document Checks settings") do
  visit doc_checks_path
  expect(page).to have_css("h1", text: "Document Checks · Investor KYC")
end

Then("I should see the document cards {string}") do |names|
  expect(page).to have_css("[data-document-name]", minimum: 1)
  expect(all("[data-document-name]").map { |card| card["data-document-name"] }).to eq(names.split(",").map(&:strip)) # rubocop:disable Rails/Pluck -- Capybara nodes, not a relation
end

Then("the Document Checks page should say {string}") do |text|
  expect(page).to have_content(text)
end

When("I click {string} on the {string} card") do |label, document_name|
  within(doc_check_card(document_name)) { click_on(label) }
end

# Adds a row and fills it the way a user would: action first, then the field
When("I add a check on the {string} card to {string} the field {string}") do |document_name, action, field_label|
  within(doc_check_card(document_name)) do
    click_on("Add a check")
    row = all("tr[data-doc-check-card-target='row']").last
    row.find("[data-role='action']").select(action)
    row.find("[data-role='field']").select(field_label)
  end
end

When("I change the last check's look for on the {string} card to {string}") do |document_name, text|
  within(doc_check_card(document_name)) do
    all("tr[data-doc-check-card-target='row']").last.find("[data-role='look-for']").fill_in(with: text)
  end
end

# Saved = the card comes back without "Unsaved changes" (a refused save keeps it, with the row errors)
When("I save the {string} card") do |document_name|
  within(doc_check_card(document_name)) { click_on("Save") }
  expect(doc_check_card(document_name)).to have_no_content("Unsaved changes"),
                                           -> { doc_check_card(document_name).text }
end

def doc_check_row_values(row)
  action = row.find("[data-role='action']")
  field = row.find("[data-role='field']", visible: :all)
  selected_field = field.disabled? ? nil : field.all("option", visible: :all).find(&:selected?)
  { "action" => action.all("option").find(&:selected?).text,
    "field" => selected_field&.text.to_s.sub(" (already used on this card)", ""),
    "look for" => row.find("[data-role='look-for']").value }
end

# | action | field | look for |  — the card's rows as shown (field by its label)
Then("the {string} card should have the checks:") do |document_name, table|
  within(doc_check_card(document_name)) do
    expect(page).to have_css("tr[data-doc-check-card-target='row']", count: table.hashes.size)
    rows = all("tr[data-doc-check-card-target='row']").map { |row| doc_check_row_values(row) }
    expect(rows).to eq(table.hashes)
  end
end

Then("the {string} card should have {int} checks") do |document_name, count|
  within(doc_check_card(document_name)) { expect(page).to have_css("tr[data-doc-check-card-target='row']", count:) }
end

Then("the new check on the {string} card should show {string} greyed out") do |document_name, label|
  within(doc_check_card(document_name)) do
    row = all("tr[data-doc-check-card-target='row']").last
    expect(row).to have_css("[data-role='field'] option[disabled]", text: label, visible: :all)
  end
end

# The card as saved, plus one more row on an already-used field (what the dropdown prevents)
When("a request saves the {string} card with a second check on the field {string}") do |document_name, field_name|
  saved = DocCheck.where(entity: @entity, document_name:).ordered.map { |c| c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES) }
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:,
                                       rows: saved + [{ "action" => "fill_in", "field_name" => field_name, "look_for" => "#{field_name} again" }])
  @card_saved = @card_form.save
end

# The card as saved, with one row's look-for edited (the field left as it is)
When("a request saves the {string} card with the look for of {string} changed to {string}") do |document_name, from, to|
  rows = DocCheck.where(entity: @entity, document_name:).ordered.map do |c|
    attrs = c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES)
    attrs["look_for"] = to if c.look_for == from
    attrs
  end
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:, rows:)
  @card_saved = @card_form.save
  expect(@card_saved).to be(true), @card_form.rows.map { |r| r.errors.full_messages }.inspect
end

Then("the {string} card should say {string}") do |document_name, text|
  within(doc_check_card(document_name)) { expect(page).to have_content(text) }
end

Then("the {string} card should not offer a preset") do |document_name|
  within(doc_check_card(document_name)) do
    expect(page).to have_button("Add a check")
    expect(page).to have_no_button(/preset/)
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

# X4: a crafted save — the dropdown never offers the field
When("a request saves a Fill in check on {string} for the field {string}") do |document_name, field_name|
  @card_form = DocChecks::CardForm.new(entity: @entity, document_name:,
                                       rows: [{ "action" => "fill_in", "field_name" => field_name, "look_for" => field_name }])
  @card_saved = @card_form.save
end

Then("the save should be refused with {string}") do |message|
  expect(@card_saved).to be(false)
  expect(@card_form.rows.flat_map { |r| r.errors[:field_name] }).to include(message)
end
