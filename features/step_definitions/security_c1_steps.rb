# Step definitions for features/security/dashboard_widget_metadata_parse.feature (C1) and
# features/security/m29_adhoc_removed.feature (M29) — docs/security/security_review_2026_10.md.
# Login, roles, the widget edit form and dynamic metadata fields reuse the shared steps
# (features/common.rb, login.rb, dashboard_widget_metadata_steps.rb).

# Builds a Fund Dashboard widget in the logged-in user's entity (not saved)
def c1_widget(widget_name, metadata)
  DashboardWidget.new(entity: @entity, dashboard_name: DashboardWidget::FUND_DASHBOARD, widget_name:,
                      tags: "C1 #{widget_name}", size: "Medium", metadata:)
end

# Form params for posting a new widget the way the widget form does
def c1_widget_params(metadata)
  { dashboard_widget: { dashboard_name: DashboardWidget::FUND_DASHBOARD, widget_name: "Fund Ratios",
                        tags: "C1 posted", size: "Medium", metadata: } }
end

# ---- C1-1 / C1-3: the form refuses an expression -----------------------------------------------

When('I post a new dashboard widget with metadata {string}') do |metadata|
  # Submit straight to create, as the widget form (or a crafted request) would
  page.driver.submit :post, dashboard_widgets_path, c1_widget_params(metadata)
end

Then('the widget is refused with the plain-values error') do
  # The form re-renders with the validation message, and nothing was stored
  expect(page).to have_content("Metadata #{DashboardWidget::METADATA_LITERAL_MESSAGE}")
  expect(DashboardWidget.where(entity_id: @entity.id, tags: "C1 posted")).not_to exist
end

# ---- C1-2: a stored expression is never run -------------------------------------------------------

Given('a {string} widget in my entity whose metadata {string} was written by update_column') do |widget_name, metadata|
  # The expression would set this marker if it ever ran
  ENV.delete("C1_2_MARKER")
  @c1_widget = c1_widget(widget_name, nil)
  @c1_widget.save!
  # update_column skips validations, as a raw SQL write or old data would
  @c1_widget.update_column(:metadata, metadata)
end

Then('the expression in the widget metadata was not run') do
  expect(ENV.fetch("C1_2_MARKER", nil)).to be_nil
end

# ---- C1-X1…X4: literals give the values eval gave -------------------------------------------------

Given('a {string} widget in my entity is saved with metadata {string}') do |widget_name, metadata|
  # create! runs metadata_must_be_literal, so this also proves the literal is accepted on save
  @c1_widget = c1_widget(widget_name, metadata)
  @c1_widget.save!
end

Given('a {string} widget in my entity is saved with metadata:') do |widget_name, metadata|
  @c1_widget = c1_widget(widget_name, metadata)
  @c1_widget.save!
end

Given('a {string} widget in my entity is saved with metadata {string} and a trailing tab') do |widget_name, metadata|
  # A tab is hard to keep in a feature file, so it is appended here
  @c1_widget = c1_widget(widget_name, "#{metadata}\t")
  @c1_widget.save!
end

When('I open that widget') do
  visit dashboard_widget_path(@c1_widget)
end

Then('the widget page renders') do
  # show.html.erb lists metadata_args; reaching the Metadata row means rendering did not raise
  expect(page).to have_content("Metadata")
  expect(page).to have_content(@c1_widget.widget_name)
end

# Expected values are written as JSON (keys symbolized, as metadata_args returns them)
Then('the widget metadata args are {string}') do |json|
  expect(@c1_widget.reload.metadata_args).to eq(JSON.parse(json, symbolize_names: true))
end

Then('the widget metadata args are:') do |json|
  expect(@c1_widget.reload.metadata_args).to eq(JSON.parse(json, symbolize_names: true))
end

# ---- C1-H: the dynamic fields still save and render -----------------------------------------------

When('I save the widget form') do
  click_on "Save"
  expect(page).to have_content("Dashboard widget was successfully updated.")
end

Then('the saved {string} widget metadata args include {string}') do |widget_name, json|
  widget = DashboardWidget.find_by!(entity_id: @entity.id, widget_name:)
  expect(widget.metadata_args).to include(JSON.parse(json, symbolize_names: true))
end

# ---- C1-X5: import keeps literal rows and reports expression rows --------------------------------

When('I import a dashboard widgets sheet with a literal row and an expression row') do
  ENV.delete("C1_X5_MARKER")
  # Build the sheet with every standard header, so only the metadata differs between the two rows
  path = Rails.root.join("tmp", "c1_x5_dashboard_widgets_#{SecureRandom.hex(4)}.xlsx")
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Widgets") do |sheet|
      sheet.add_row ImportDashboardWidget::STANDARD_HEADERS
      sheet.add_row ["Fund Dashboard", "Fund Ratios", 1, "C1 kept", "{title: 'Kept', months: 12}", "Medium", "Yes", "Yes", "No", "Default", "No"]
      sheet.add_row ["Fund Dashboard", "Fund Ratios", 2, "C1 refused", "{title: ENV.store('C1_X5_MARKER', 'ran')}", "Medium", "Yes", "Yes", "No", "Default", "No"]
    end
    p.serialize(path.to_s)
  end
  # Run the import the same way the shared import step does
  @c1_import = ImportUpload.create!(entity: @entity, owner: @entity, import_type: "DashboardWidget", name: "C1-X5 import",
                                    user_id: @user.id, import_file: File.open(path))
  ImportUploadJob.perform_now(@c1_import.id)
  @c1_import.reload
end

Then('the literal row is saved and the expression row is reported') do
  # One row saved, one row failed
  expect(@c1_import.processed_row_count).to eq(1)
  expect(@c1_import.failed_row_count).to eq(1)
  kept = DashboardWidget.find_by!(entity_id: @entity.id, tags: "C1 kept")
  expect(kept.metadata_args).to eq({ title: "Kept", months: 12 })
  expect(DashboardWidget.where(entity_id: @entity.id, tags: "C1 refused")).not_to exist
  # The failed row (spreadsheet row 3) names the plain-values rule
  error = @c1_import.row_errors.find { |e| e["row"] == 3 }
  expect(error["message"]).to include(DashboardWidget::METADATA_LITERAL_MESSAGE)
  # ...and the expression was never run
  expect(ENV.fetch("C1_X5_MARKER", nil)).to be_nil
end

# ---- M29-1: the AiPolars / account_entries#adhoc path is gone -----------------------------------

Then('the account entries adhoc endpoint no longer exists') do
  # POST /account_entries/adhoc has no route at all
  expect { Rails.application.routes.recognize_path("/account_entries/adhoc", method: :post) }
    .to raise_error(ActionController::RoutingError)
  # GET only matches the generic show route (id "adhoc"), never an adhoc action
  expect(Rails.application.routes.recognize_path("/account_entries/adhoc", method: :get)[:action]).to eq("show")
  # The action, its policy predicate and the eval'ing service are all deleted
  expect(AccountEntriesController.action_methods).not_to include("adhoc")
  expect(AccountEntryPolicy.method_defined?(:adhoc?)).to be false
  expect(Object.const_defined?(:AiPolars)).to be false
end
