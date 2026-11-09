# Steps for features/core/custom_form_editor.feature — the custom form edit page (form_types/_form,
# fcf_editor_controller.js): the fields listed by step on the left, one field's settings on the right.

# ── Helpers ────────────────────────────────────────────────────────────────────────────────────────────────────

# The field of the form under test with this label
def cfe_field(label)
  @form_type.form_custom_fields.reload.find_by!(label: label)
end

# The list row for a label (exact, so "Founder" never matches "Founder name")
def cfe_row_xpath(label)
  "//li[@data-fcf-row][.//div[contains(@class,'fcf-row-label')][normalize-space()='#{label}']]"
end

# What a field holds, with blank values treated alike: the page has always submitted "" for an empty box (and {} for
# no validation rules), which is not a change the editor made
def cfe_comparable(fcf)
  fcf.attributes.except("updated_at", "created_at").transform_values(&:presence)
end

# ── Setup ──────────────────────────────────────────────────────────────────────────────────────────────────────

# Starts the record type's Default form with exactly these fields (any the entity came with are removed)
Given('the {string} custom form has the fields:') do |class_name, table|
  @form_type = @entity.form_types.where(name: class_name, tag: "Default").first_or_initialize
  @form_type.save!(validate: false) if @form_type.new_record?
  @form_type.form_custom_fields.destroy_all
  table.hashes.each do |row|
    fcf = @form_type.form_custom_fields.create!(name: FormCustomField.to_name(row["label"]), label: row["label"],
                                                field_type: row["field_type"], meta_data: row["meta_data"].presence,
                                                step: row["step"])
    # Exact positions, whatever acts_as_list chose on create
    fcf.update_column(:position, row["position"].to_i)
  end
end

# A calculation: hidden from users who are not CapHive support, so the editor never shows or submits it
Given('the {string} custom form also has a hidden calculation field at position {int}') do |_class_name, position|
  @hidden_fcf = @form_type.form_custom_fields.new(name: "calc_total", label: "Calc total", field_type: "Calculation", meta_data: "1")
  @hidden_fcf.save!(validate: false)
  @hidden_fcf.update_column(:position, position)
end

Given('the {string} custom form\'s {string} field has the older type {string}') do |_class_name, label, field_type|
  cfe_field(label).update_column(:field_type, field_type)
end

Given('I note every field of the {string} custom form') do |_class_name|
  @cfe_before = @form_type.form_custom_fields.reload.order(:id).map { |fcf| cfe_comparable(fcf) }
end

# ── The page ───────────────────────────────────────────────────────────────────────────────────────────────────

When('I open the custom form editor for {string}') do |_class_name|
  visit edit_form_type_path(@form_type)
  expect(page).to have_css(".fcf-editor.fcf-ready")
end

When('I save the custom form') do
  click_on "Save"
  expect(page).to have_content("Form type was successfully updated")
  @form_type.reload
end

When('I save the custom form expecting an error') do
  click_on "Save"
  expect(page).to have_content("prohibited this form_type from being saved")
  expect(page).to have_css(".fcf-editor.fcf-ready")
end

When('I open the {string} field in the form editor') do |label|
  find(:xpath, cfe_row_xpath(label)).click
  expect(page).to have_css(".fcf-pane.active [data-fcf-label]")
  expect(find(".fcf-pane.active [data-fcf-label]").value).to eq(label)
end

Then('the form editor lists {string} under {string}') do |labels, heading|
  rows = all(:xpath, "//div[@data-fcf-step-head][span[1][normalize-space()='#{heading}']]/following-sibling::ul[1]//div[contains(@class,'fcf-row-label')]")
  expect(rows.map { |row| row.text.strip }).to eq(labels.split(",").map(&:strip))
end

Then('the form editor shows the {string} field\'s settings only') do |label|
  expect(page).to have_css(".fcf-pane", count: 1)
  expect(find(".fcf-pane.active [data-fcf-label]").value).to eq(label)
end

Then('the form editor shows {string}') do |text|
  expect(find("[data-fcf-editor-target='dirty']")).to have_text(text)
end

When('I follow the {string} breadcrumb') do |text|
  find(".breadcrumb a", text: text, exact_text: true).click
end

# ── One field's settings ───────────────────────────────────────────────────────────────────────────────────────

When('I add the choice {string} in the form editor') do |choice|
  within(".fcf-pane.active") do
    input = find(".fcf-chip-input")
    input.fill_in(with: choice)
    input.send_keys(:enter)
    expect(page).to have_css(".fcf-chip", text: choice)
  end
end

When('I remove the choice {string} in the form editor') do |choice|
  within(".fcf-pane.active") do
    find(".fcf-chip", text: choice, exact_text: true).find(".fcf-chip-x").click
    expect(page).to have_no_css(".fcf-chip", text: choice, exact_text: true)
  end
end

Then('the form editor preview offers {string}') do |choices|
  within(".fcf-pane.active [data-fcf-preview]") do
    expect(all("option").map(&:text)).to eq(choices.split(",").map(&:strip))
  end
end

When('I pick {int} decimal places in the form editor') do |places|
  within(".fcf-pane.active") { find("[data-fcf-number-precision]").select(places.to_s) }
end

When('I set the form editor condition to {string} {string} {string}') do |field, criteria, value|
  within(".fcf-pane.active") do
    find("[data-fcf-condition-on]").select(field)
    find("select[name$='[condition_criteria]']").select(criteria)
    find("[data-fcf-condition-value]").fill_in(with: value)
  end
end

When('I make the field visible only to me in the form editor') do
  within(".fcf-pane.active") do
    find("[data-fcf-visible-mode]").select("Only these users…")
    find("[data-fcf-user-picker] label", text: @user.email).click
    expect(page).to have_css("[data-fcf-user-picker] .fcf-chip", text: @user.email)
  end
end

# The switches are the app's ios-toggle: the real checkbox is hidden, its slider is clicked
When('I turn on {string} in the form editor') do |flag|
  within(".fcf-pane.active") do
    checkbox = find("input[type=checkbox][data-fcf-flag='#{flag}']", visible: :all)
    find("input[type=checkbox][data-fcf-flag='#{flag}'] + .ios-toggle-slider").click unless checkbox.checked?
  end
end

# Waiting matchers: the switches change on a click's change event, so a one-off read can come too early
Then('the form editor has {string} on and {string} off') do |on, off|
  within(".fcf-pane.active") do
    expect(page).to have_css("input[type=checkbox][data-fcf-flag='#{on}']:checked", visible: :all)
    expect(page).to have_no_css("input[type=checkbox][data-fcf-flag='#{off}']:checked", visible: :all)
  end
end

When('I add the field {string} in the form editor') do |label|
  click_on "Add Field"
  within(".fcf-pane.active") { find("[data-fcf-label]").fill_in(with: label) }
end

Then('the form editor\'s stored name for the new field is {string}') do |name|
  within(".fcf-pane.active") { expect(find("[data-fcf-name-input]").value).to eq(name) }
end

When('I change the form editor label to {string}') do |label|
  within(".fcf-pane.active") { find("[data-fcf-label]").fill_in(with: label) }
end

Then('the form editor label is {string}') do |label|
  expect(find(".fcf-pane.active [data-fcf-label]").value).to eq(label)
end

# Drag one row onto another: dropped on the lower half it goes below. The target is first scrolled to the middle of
# the screen: Playwright only scrolls it just into view, which can leave it under the sticky Save bar, and the drop
# then lands on the bar instead of the row.
When('I drag {string} below {string} in the form editor') do |dragged, target|
  # The editor's own HTML5 drag events, fired on the two rows: dragstart on the dragged row, then dragover + drop on
  # the lower part of the target row, which is what the drop handler reads ("after" = below the row's middle).
  # Playwright's mouse drag_to used to do this, but the field list scrolls in its own container: when the target
  # needed bringing into view, Playwright scrolled that container between mouse-down and mouse-move, Chromium never
  # started a drag, and the step silently did nothing ("1 unsaved change" never appeared). Diagnosed 2026-11-09:
  # mousedown/mouseup fired, dragstart never did. The editor's drop handling (move, renumber, unsaved count) runs
  # exactly as for a real drag.
  page.execute_script(<<~JS, cfe_row_xpath(dragged), cfe_row_xpath(target))
    const [draggedXpath, targetXpath] = arguments
    const row = (xpath) => document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue
    const source = row(draggedXpath)
    const goal = row(targetXpath)
    goal.scrollIntoView({ block: "center", behavior: "instant" })
    const box = goal.getBoundingClientRect()
    const transfer = new DataTransfer()
    const fire = (el, type, y) => el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: transfer, clientX: box.left + 40, clientY: y }))
    fire(source, "dragstart", source.getBoundingClientRect().top + 5)
    fire(goal, "dragover", box.bottom - 4)
    fire(goal, "drop", box.bottom - 4)
  JS
end

When('I drag {string} onto the {string} heading in the form editor') do |dragged, heading|
  page.driver.with_playwright_page do |pw|
    head = pw.locator("xpath=//div[@data-fcf-step-head][span[1][normalize-space()='#{heading}']]")
    head.evaluate("el => el.scrollIntoView({ block: 'center' })") # clear of the sticky Save bar (see above)
    pw.locator("xpath=#{cfe_row_xpath(dragged)}").drag_to(head, targetPosition: { x: 20, y: 5 })
  end
end

# ── What was stored ────────────────────────────────────────────────────────────────────────────────────────────

Then('every field of the {string} custom form is unchanged') do |_class_name|
  after = @form_type.form_custom_fields.reload.order(:id).map { |fcf| cfe_comparable(fcf) }
  expect(after).to eq(@cfe_before)
end

Then('the {string} field\'s meta data is {string}') do |label, meta_data|
  expect(cfe_field(label).meta_data).to eq(meta_data)
end

Then('the {string} custom form\'s fields are ordered {string}') do |_class_name, labels|
  expected = labels.split(",").map(&:strip)
  ordered = @form_type.form_custom_fields.reload.where(label: expected).order(:position).pluck(:label)
  expect(ordered).to eq(expected)
end

Then('the hidden calculation field is still at position {int}') do |position|
  expect(@hidden_fcf.reload.position).to eq(position)
end

Then('the {string} field is on step {string}') do |label, step|
  expect(cfe_field(label).step).to eq(step)
end

Then('the {string} field shows only when {string} {string} {string}') do |label, condition_on, criteria, value|
  fcf = cfe_field(label)
  expect([fcf.condition_on, fcf.condition_criteria, fcf.condition_params]).to eq([condition_on, criteria, value])
end

Then('the {string} field is shown only to me') do |label|
  expect(cfe_field(label).show_user_ids).to eq(@user.id.to_s)
end

Then('the {string} custom form has a field {string} placed last') do |_class_name, name|
  fields = @form_type.form_custom_fields.reload
  expect(fields.find_by!(name: name).position).to eq(fields.maximum(:position))
end

Then('the {string} custom form has no field {string}') do |_class_name, name|
  expect(@form_type.form_custom_fields.reload.where(name: name)).not_to exist
end

Then('the {string} field\'s type is {string}') do |label, field_type|
  expect(cfe_field(label).field_type).to eq(field_type)
end
