# Steps for choosing a table's columns in the side panel and on Configure Grids.
# openspec/changes/grid-columns-inline-settings/business-rules.md (§1 table columns)
# Reuses: 'Im logged in as a user …', 'the user has role …', 'there is an investor named …', 'I am acting as an
# investor', 'I press Escape', 'a saved message should say …'.

module GridColumnsSteps
  # Wait for a condition that a save or a frame reload makes true
  def gcs_eventually(timeout = 15)
    deadline = Time.current + timeout
    loop do
      return if yield
      raise Capybara::ExpectationNotMet, "condition not met within #{timeout}s" if Time.current > deadline

      sleep 0.2
    end
  rescue Capybara::Playwright::Node::StaleReferenceError
    retry
  end

  def gcs_model(name) = name.constantize

  # The form type the tables read (lowest id of that name)
  def gcs_form_type(model_name, entity = @entity)
    GridColumnsContext.form_type_for(entity, gcs_model(model_name))
  end

  def gcs_find_or_create_form_type(model_name, entity = @entity)
    gcs_form_type(model_name, entity) || FormType.create!(entity:, name: model_name)
  end

  # Saved column keys of an owner, cleaned, in order
  def gcs_saved_keys(owner)
    return [] unless owner

    owner.grid_view_preferences.reload.order(:sequence).map(&:clean_key)
  end

  # Saved rows for an owner from clean keys: each key takes its label and full "key; css" from the model's
  # standard columns, the column options, or (custom fields) its humanized name
  def gcs_save_columns(owner, model_name, keys)
    model = gcs_model(model_name)
    options = GridColumnOptions.new(model, owner.entity_id).call.values.reduce({}) { |all, group| all.merge(group) }
    all = model::STANDARD_COLUMNS.merge(options)
    owner.grid_view_preferences.destroy_all
    keys.each.with_index(1) do |key, position|
      label, full_key = all.find { |_l, k| GridColumnOptions.clean(k) == key } || [key.delete_prefix("custom_fields.").humanize, key]
      owner.grid_view_preferences.create!(key: full_key, name: label, entity_id: owner.entity_id, sequence: position)
    end
  end

  def gcs_keys(list) = list.split(",").map(&:strip).reject(&:blank?)

  # The open side panel, or the editor on Configure Grids
  def gcs_editor
    page.has_css?(".grid-columns-panel.show", wait: 0) ? find(".grid-columns-panel.show") : find(".grid-columns-editor")
  end

  # A row of the editor by its clean key
  def gcs_row_xpath(key)
    "//li[@data-grid-columns-row][@data-key='#{key}' or starts-with(@data-key, '#{key};')]"
  end

  def gcs_row(key)
    gcs_editor.find(:xpath, ".#{gcs_row_xpath(key)}")
  end

  def gcs_row_labels
    gcs_editor.all("[data-grid-columns-form-target='list'] [data-grid-columns-row] [data-grid-columns-label]").map(&:value)
  end

  # Headings of the table on the page (visible or folded away by the responsive table)
  def gcs_headings(table_id)
    all("table##{table_id} thead th", visible: :all).map { |th| gcs_heading_text(th) }.reject { |t| t.blank? || t == "Actions" }
  end

  # A heading's text without the sort arrows
  def gcs_heading_text(th)
    th.text(:all).gsub(/[▲▼]/, "").squish
  end

  # A signed context for a direct request: the owner's standard columns, as Configure Grids builds it
  def gcs_token_for(owner)
    GridColumnsContext.for_owner(owner).to_token
  end

  # A direct request (rack_test), status kept. rack_test's submit blanks a GET's query string (form semantics), so
  # the query moves into the params, as security_core_medium_a_steps.rb#cma_request does
  def gcs_request(method, path, params = {})
    uri = URI.parse(path)
    if method.to_s.casecmp?("get") && uri.query.present?
      params = Rack::Utils.parse_nested_query(uri.query).merge(params)
      path = uri.path
    end
    page.driver.submit(method, path, params)
    @gcs_status = page.status_code
  rescue ActiveRecord::RecordNotFound
    @gcs_status = 404
  end

  def gcs_other_entity
    @gcs_other_entity ||= FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital #{SecureRandom.hex(2)}")
  end

  def gcs_report(name, url:, entity: @entity, user: @user, category: nil)
    Report.create!(name:, url:, entity:, user:, curr_role: user.curr_role, category:)
  end
end
World(GridColumnsSteps)

# --- Setup ------------------------------------------------------------------------------------------------------

Given("my firm's {string} form type has a text field {string}") do |model_name, field|
  form_type = gcs_find_or_create_form_type(model_name)
  FormCustomField.create!(form_type:, name: field, label: field.humanize, field_type: "TextField")
end

Given("the investor {string} has {string} set to {string}") do |investor_name, field, value|
  investor = Investor.find_by!(investor_name:)
  investor.json_fields = investor.json_fields.merge(field => value)
  investor.save!(validate: false)
end

Given("my firm's {string} columns are {string}") do |model_name, keys|
  gcs_save_columns(gcs_find_or_create_form_type(model_name), model_name, gcs_keys(keys))
end

Given("my firm's {string} columns include the derived field {string} with key {string}") do |model_name, label, key|
  owner = gcs_find_or_create_form_type(model_name)
  owner.grid_view_preferences.create!(key:, name: label, derived_field: true, data_type: "String", alignment: "text-center",
                                      entity_id: owner.entity_id, sequence: owner.grid_view_preferences.maximum(:sequence).to_i + 1)
end

Given("my firm has no saved {string} columns") do |model_name|
  gcs_form_type(model_name)&.grid_view_preferences&.destroy_all
end

Given("my firm has no {string} form type") do |model_name|
  FormType.where(entity: @entity, name: model_name).destroy_all
end

Given("my firm has {string} form types tagged {string}") do |model_name, tags|
  FormType.where(entity: @entity, name: model_name).destroy_all
  tags.split(",").map(&:strip).each { |tag| FormType.create!(entity: @entity, name: model_name, tag:) }
end

Given("a report {string} on {string} with columns {string}") do |name, url, keys|
  @gcs_report = gcs_report(name, url:)
  gcs_save_columns(@gcs_report, @gcs_report.model, gcs_keys(keys))
end

Given("a report {string} on {string} with no columns") do |name, url|
  @gcs_report = gcs_report(name, url:)
end

Given("there is a fund {string} with no commitments") do |name|
  @gcs_fund = FactoryBot.create(:fund, entity: @entity, name:)
end

Given("another firm has a report {string} on {string} with columns {string}") do |name, url, keys|
  other_user = FactoryBot.create(:user, entity: gcs_other_entity)
  @gcs_other_report = gcs_report(name, url:, entity: gcs_other_entity, user: other_user)
  gcs_save_columns(@gcs_other_report, @gcs_other_report.model, gcs_keys(keys))
end

Given("another user of my firm has a draft report {string} on {string} with columns {string}") do |name, url, keys|
  other_user = FactoryBot.create(:user, entity: @entity)
  @gcs_draft_report = gcs_report(name, url:, user: other_user, category: ReportPolicy::AI_DRAFT)
  gcs_save_columns(@gcs_draft_report, @gcs_draft_report.model, gcs_keys(keys))
end

Given("another firm has an {string} form type") do |model_name|
  @gcs_other_form_type = FormType.create!(entity: gcs_other_entity, name: model_name)
end

Given("I am signed in as a plain employee of my firm") do
  employee = FactoryBot.create(:user, entity: @entity)
  employee.roles.where(name: "company_admin").each { |role| employee.remove_role(role.name.to_sym) }
  @user = employee
  log_in(employee)
end

# --- Pages and the panel ----------------------------------------------------------------------------------------

When("I open the {string} page") do |path|
  visit path.gsub("{fund}", @gcs_fund&.id.to_s).gsub("{report}", @gcs_report&.id.to_s)
end

When("I open the commitments of the investor {string}") do |investor_name|
  visit capital_commitments_path(investor_id: Investor.find_by!(investor_name:).id)
end

When("I open Configure Grids for my firm's {string} form type") do |model_name|
  visit configure_grids_grid_view_preferences_path(owner_type: "FormType", owner_id: gcs_form_type(model_name).id)
end

When("I open Configure Grids for my firm's {string} form type tagged {string}") do |model_name, tag|
  form_type = FormType.find_by!(entity: @entity, name: model_name, tag:)
  visit configure_grids_grid_view_preferences_path(owner_type: "FormType", owner_id: form_type.id)
end

When("I open Configure Grids for the report") do
  visit configure_grids_grid_view_preferences_path(owner_type: "Report", owner_id: @gcs_report.id)
end

Then("the columns button should be beside the search box") do
  expect(page).to have_css(".search-form .grid-columns-btn.in-search", wait: 20)
end

Then("the columns button should be at the table's corner") do
  expect(page).to have_css(".grid-columns-host > .grid-columns-btn", wait: 20)
  expect(page).to have_no_css(".grid-columns-btn.in-search")
end

Then("there should be no columns button") do
  expect(page).to have_no_css(".grid-columns-btn", visible: :all)
end

When("I open the columns panel") do
  find(".grid-columns-btn", match: :first, wait: 20).click
  expect(page).to have_css(".grid-columns-panel.show [data-grid-columns-form-target='list']", wait: 30)
end

Then("the columns panel should be titled {string}") do |title|
  expect(find(".grid-columns-panel.show .offcanvas-title")).to have_text(title)
end

Then("the columns editor should list {string}") do |labels|
  gcs_eventually { gcs_row_labels == gcs_keys(labels) }
end

Then("the columns editor should not list {string}") do |label|
  expect(gcs_row_labels).not_to include(label)
end

Then("the column {string} should be locked") do |key|
  row = gcs_row(key)
  expect(row["data-locked"]).to eq("true")
  expect(row).to have_text("Always shown")
end

Then("the column {string} should not be locked") do |key|
  expect(gcs_row(key)["data-locked"]).to eq("false")
end

Then("the column {string} should be marked not shown on this page") do |key|
  expect(gcs_row(key)).to have_css("[data-grid-columns-hidden]")
end

When("I move the column {string} above {string}") do |key, other|
  gcs_row(key)
  gcs_row(other)
  # A real HTML5 drag (Playwright's locator API), dropped on the upper edge of the target row
  page.driver.with_playwright_page do |pw|
    pw.locator("xpath=#{gcs_row_xpath(key)}").drag_to(pw.locator("xpath=#{gcs_row_xpath(other)}"), targetPosition: { x: 40, y: 3 })
  end
end

When("I rename the column {string} to {string}") do |key, label|
  gcs_row(key).find("[data-grid-columns-label]").fill_in(with: label)
end

When("I clear the heading of the column {string}") do |key|
  gcs_row(key).find("[data-grid-columns-label]").fill_in(with: "")
end

When("I remove the column {string}") do |key|
  gcs_row(key).find(".grid-columns-remove").click
end

When("I remove every column") do
  gcs_editor.all("[data-grid-columns-row][data-locked='false'] .grid-columns-remove").each(&:click)
end

# The add list is searchable (select2); the steps pick through the underlying select
When("I add the column {string}") do |label|
  select = gcs_editor.find("#grid_columns_add", visible: :all)
  value = select.all("option", visible: :all).find { |o| o.text(:all).strip == label }&.value
  raise "No column #{label} offered" unless value

  execute_script(<<~JS, select.native, value)
    const [sel, value] = arguments; sel.value = value; sel.dispatchEvent(new Event("change", { bubbles: true }));
  JS
end

When("I add the first column offered under {string}") do |group|
  select = gcs_editor.find("#grid_columns_add", visible: :all)
  option = select.all("optgroup[label='#{group}'] option", visible: :all).first
  @gcs_added_key = option.value
  execute_script(<<~JS, select.native, option.value)
    const [sel, value] = arguments; sel.value = value; sel.dispatchEvent(new Event("change", { bubbles: true }));
  JS
end

When("I add the derived field {string} with key {string}") do |label, key|
  editor = gcs_editor
  editor.find("[data-grid-columns-derived] summary").click
  editor.find("[data-grid-columns-form-target='derivedLabel']").fill_in(with: label)
  editor.find("[data-grid-columns-form-target='derivedKey']").fill_in(with: key)
  editor.find("[data-grid-columns-add-derived]").click
end

When("I set the column {string} to data type {string} and alignment {string}") do |key, data_type, alignment|
  row = gcs_row(key)
  row.find("[data-action='grid-columns-form#toggleDetails']").click
  row.find("[data-grid-columns-type]").select(data_type)
  row.find("[data-grid-columns-align]").select(alignment)
end

When("I change the key of the derived column {string} to {string}") do |key, new_key|
  row = gcs_row(key)
  row.find("[data-action='grid-columns-form#toggleDetails']").click
  row.find("[data-grid-columns-dkey]").fill_in(with: new_key)
end

When("I reset to the standard columns") do
  gcs_editor.find("[data-grid-columns-reset]").click
  expect(gcs_editor).to have_css("[data-grid-columns-reset-note]:not(.d-none)")
end

When("I save the columns") do
  @gcs_saved_at = Time.current
  gcs_editor.find("[data-grid-columns-save]").click
end

Then("the columns panel should close") do
  expect(page).to have_no_css(".grid-columns-panel.show", wait: 30)
end

Then("the columns editor should say {string}") do |message|
  expect(page).to have_css("[data-grid-columns-errors]", text: message, wait: 20)
end

Then("the columns panel should still be open") do
  expect(page).to have_css(".grid-columns-panel.show")
end

# --- What the table shows -----------------------------------------------------------------------------------

Then("the {string} table headings should be {string}") do |table_id, labels|
  gcs_eventually { gcs_headings(table_id) == gcs_keys(labels) }
rescue Capybara::ExpectationNotMet
  raise Capybara::ExpectationNotMet, "headings were #{gcs_headings(table_id).inspect}"
end

Then("the {string} table headings should include {string}") do |table_id, label|
  gcs_eventually { gcs_headings(table_id).include?(label) }
end

Then("the {string} table should show {string}") do |table_id, text|
  expect(find("table##{table_id}", visible: :all)).to have_text(text, wait: 20)
end

Then("the {string} column heading of the {string} table should be right-aligned") do |label, table_id|
  gcs_eventually do
    th = all("table##{table_id} thead th", visible: :all).find { |h| gcs_heading_text(h) == label }
    th && th[:class].to_s.split.include?("text-end")
  end
end

Then("the search box should still say {string}") do |text|
  expect(find("#search_input").value).to eq(text)
end

When("I search the table for {string}") do |text|
  find("#search_input").fill_in(with: text)
  find("#search_input").send_keys(:enter)
  sleep 1.5
end

Then("I should still be on the fund page") do
  expect(page).to have_current_path(fund_path(@gcs_fund), ignore_query: true)
end

# --- Saved state ------------------------------------------------------------------------------------------------

Then("my firm's {string} columns should be {string}") do |model_name, keys|
  gcs_eventually { gcs_saved_keys(gcs_form_type(model_name)) == gcs_keys(keys) }
end

Then("my firm should have no saved {string} columns") do |model_name|
  gcs_eventually { gcs_saved_keys(gcs_form_type(model_name)).empty? }
end

Then("my firm's {string} form type should exist tagged {string} with {int} columns") do |model_name, tag, count|
  gcs_eventually { (ft = gcs_form_type(model_name)) && ft.tag == tag && gcs_saved_keys(ft).size == count }
end

Then("the report's columns should be {string}") do |keys|
  gcs_eventually { gcs_saved_keys(@gcs_report) == gcs_keys(keys) }
end

Then("my firm's {string} column {string} should have heading {string}") do |model_name, key, label|
  gcs_eventually do
    pref = gcs_form_type(model_name).grid_view_preferences.reload.find { |p| p.clean_key == key }
    pref && pref.clean_label == label
  end
end

Then("my firm's {string} column {string} should store no heading override") do |model_name, key|
  pref = gcs_form_type(model_name).grid_view_preferences.reload.find { |p| p.clean_key == key }
  expect(pref[:label]).to be_nil
end

Then("my firm's derived {string} column should have key {string}, data type {string}, alignment {string}, heading {string} at position {int}") do |model_name, key, data_type, alignment, label, position|
  gcs_eventually do
    pref = gcs_form_type(model_name).grid_view_preferences.reload.find_by(derived_field: true)
    pref && [pref.key, pref.data_type, pref.alignment.to_s, pref.clean_label, pref.sequence] == [key, data_type, alignment, label, position]
  end
end

Then("my firm's {string} column {string} should have data type {string} and alignment {string}") do |model_name, key, data_type, alignment|
  gcs_eventually do
    pref = gcs_form_type(model_name).grid_view_preferences.reload.find { |p| p.clean_key == key }
    pref && pref.data_type == data_type && pref.alignment == alignment
  end
end

Then("the {string} form type tagged {string} should have columns {string}") do |model_name, tag, keys|
  form_type = FormType.find_by!(entity: @entity, name: model_name, tag:)
  gcs_eventually { gcs_saved_keys(form_type) == gcs_keys(keys) }
end

Then("the {string} form type tagged {string} should have no columns") do |model_name, tag|
  expect(gcs_saved_keys(FormType.find_by!(entity: @entity, name: model_name, tag:))).to be_empty
end

When("someone else removes my firm's {string} column {string}") do |model_name, key|
  gcs_form_type(model_name).grid_view_preferences.find { |p| p.clean_key == key }.destroy!
end

Then("the column added from the related group should be saved") do
  gcs_eventually { gcs_saved_keys(gcs_form_type("CapitalCommitment")).include?(GridColumnOptions.clean(@gcs_added_key)) }
  expect(GridColumnOptions.clean(@gcs_added_key)).to include(".")
end

# --- Configure Grids page ---------------------------------------------------------------------------------------

Then("every saved column should have Show, Edit and Delete") do
  rows = all(".grid-columns-editor [data-grid-columns-form-target='list'] [data-grid-columns-row]")
  expect(rows).not_to be_empty
  rows.each do |row|
    expect(row).to have_css("[data-grid-columns-show]")
    expect(row).to have_css("[data-grid-columns-edit]")
    expect(row).to have_css("[data-grid-columns-delete]")
  end
end

When("I delete the column {string} and confirm") do |key|
  gcs_row(key).find("[data-grid-columns-delete]").click
  click_on("Proceed")
end

When("I open Show for the column {string}") do |key|
  gcs_row(key).find("[data-grid-columns-show]").click
end

Then("the detail panel should show the column {string}") do |label|
  expect(page).to have_css("turbo-frame#grid_column_detail [data-grid-column-detail]", text: label, wait: 20)
end

# --- Direct requests (rack_test) -------------------------------------------------------------------------------

When("I save the {string} columns {string} directly") do |model_name, keys|
  owner = gcs_find_or_create_form_type(model_name)
  rows = gcs_keys(keys).map { |key| { key:, label: "" } }
  gcs_request(:patch, save_grid_columns_path, { context: gcs_token_for(owner), rows: rows.to_json })
end

When("I save the {string} columns {string} directly twice") do |model_name, keys|
  2.times { step %(I save the "#{model_name}" columns "#{keys}" directly) }
end

When("I save the {string} columns {string} directly with extra fields") do |model_name, keys|
  owner = gcs_find_or_create_form_type(model_name)
  rows = gcs_keys(keys).map { |key| { key:, label: "" } }
  gcs_request(:patch, save_grid_columns_path, { context: gcs_token_for(owner), rows: rows.to_json,
                                                entity_id: gcs_other_entity.id, owner_id: 0, owner_type: "Report", data_type: "HTML" })
end

When("I save the {string} column {string} with data type {string} directly") do |model_name, key, data_type|
  owner = gcs_find_or_create_form_type(model_name)
  gcs_request(:patch, save_grid_columns_path, { context: gcs_token_for(owner), rows: [{ key:, label: "", data_type: }].to_json })
end

When("I request the columns panel for my firm's {string} form type") do |model_name|
  gcs_request(:get, settings_grid_columns_path(context: gcs_token_for(gcs_find_or_create_form_type(model_name))))
end

When("I request the columns panel with an altered record") do
  token = gcs_token_for(gcs_find_or_create_form_type("Investor"))
  gcs_request(:get, settings_grid_columns_path(context: "#{token[0..-3]}xx"))
end

When("I save the {string} columns {string} with a record from 13 hours ago") do |model_name, keys|
  token = travel_to(13.hours.ago) { gcs_token_for(gcs_find_or_create_form_type(model_name)) }
  gcs_request(:patch, save_grid_columns_path, { context: token, rows: gcs_keys(keys).map { |key| { key:, label: "" } }.to_json })
end

When("I request the columns panel for a record type without standard columns") do
  token = GridColumnsContext.verifier.generate({ "m" => "Kernel", "e" => @entity.id, "s" => [] }, purpose: :grid_columns,
                                                                                                  expires_in: 1.hour)
  gcs_request(:get, settings_grid_columns_path(context: token))
end

When("I save columns {string} for the other firm's report directly") do |keys|
  token = GridColumnsContext.new(model_class: @gcs_other_report.model.constantize, entity: @gcs_other_report.entity,
                                 report: @gcs_other_report, shown: []).to_token
  gcs_request(:patch, save_grid_columns_path, { context: token, rows: gcs_keys(keys).map { |key| { key:, label: "" } }.to_json })
end

When("I save columns {string} for the draft report directly") do |keys|
  token = GridColumnsContext.new(model_class: @gcs_draft_report.model.constantize, entity: @entity,
                                 report: @gcs_draft_report, shown: []).to_token
  gcs_request(:patch, save_grid_columns_path, { context: token, rows: gcs_keys(keys).map { |key| { key:, label: "" } }.to_json })
end

When("I open Configure Grids for the other firm's {string} form type") do |_model_name|
  gcs_request(:get, configure_grids_grid_view_preferences_path(owner_type: "FormType", owner_id: @gcs_other_form_type.id))
end

# A refusal redirects (Pundit) or is not found: either way no editor and no saved marker come back
Then("the columns request should be refused") do
  expect(page).to have_no_css(".grid-columns-editor")
  expect(page).to have_no_css("[data-grid-columns-saved]", visible: :all)
end

Then("the columns save should be refused with {string}") do |message|
  expect(@gcs_status).to eq(422)
  expect(page).to have_text(message)
end

Then("the other firm's report columns should still be {string}") do |keys|
  expect(gcs_saved_keys(@gcs_other_report)).to eq(gcs_keys(keys))
end

Then("the draft report's columns should still be {string}") do |keys|
  expect(gcs_saved_keys(@gcs_draft_report)).to eq(gcs_keys(keys))
end

Then("my firm's {string} columns should be {string}, all my firm's, with their own data types") do |model_name, keys|
  owner = gcs_form_type(model_name)
  expect(gcs_saved_keys(owner)).to eq(gcs_keys(keys))
  owner.grid_view_preferences.each do |pref|
    expect(pref.entity_id).to eq(@entity.id)
    expect(pref.owner).to eq(owner)
    expect(pref.data_type).not_to eq("HTML")
  end
end

# --- AG grids (phase 3) -------------------------------------------------------------------------------------

When("I open the AG commitments grid of the investor {string}") do |investor_name|
  visit capital_commitments_path(ag: true, investor_id: Investor.find_by!(investor_name:).id)
end

# H9 — the grid's own column list (its header or its Columns side bar) names the column
Then("the AG grid should show the column {string}") do |label|
  expect(page).to have_css(".ag-header-cell-text, .ag-column-select-column-label", text: label, visible: :all, wait: 30)
end
