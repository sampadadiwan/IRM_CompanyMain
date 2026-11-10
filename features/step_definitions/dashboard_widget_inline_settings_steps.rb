# Steps for the widget settings popup on dashboards.
# openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings/design.md#worked-examples
# Reuses: 'the {string} widget on the {string} has settings {string}', 'I open the {string} of fund {string}',
# 'I open the fund dashboard {string}', 'I open the stakeholders portfolio dashboard', 'the fund {string} holds:'
# and the LP steps of lp_portfolio_steps.rb.

module DashboardWidgetInlineSettingsSteps
  # The widget's container on the page (id = parameterised widget name + position)
  def wis_container(widget_name)
    find(".dashboard-widget-container[id^='#{widget_name.parameterize.underscore}_']", visible: :all)
  end

  # The open settings popup
  def wis_modal
    find(".widget-settings-panel.show")
  end

  # A field of the popup by its label (the settings labels have no `for`, so go through the label's parent)
  def wis_field(label)
    wis_modal.find("label", text: label, exact_text: true).find(:xpath, "..").find("input:not([type=hidden]), select")
  end

  # A saved widget of my firm's Default layout
  def wis_widget(widget_name, dashboard_name)
    DashboardWidget.where(entity_id: @user.entity_id, dashboard_name:, name: "Default", widget_name:).order(:position).first!
  end

  # Settings compared as parsed values, so spacing and quoting do not matter
  def wis_args(metadata)
    DashboardWidget.new(metadata:).metadata_args
  end

  # Wait for a condition that a background save makes true
  def wis_eventually(timeout = 10)
    deadline = Time.current + timeout
    loop do
      return if yield
      raise Capybara::ExpectationNotMet, "condition not met within #{timeout}s" if Time.current > deadline

      # Kept: the poll interval of this wait loop, not a fixed wait
      sleep 0.2
    end
  end

  # Another firm, created once per scenario
  def wis_other_entity
    @wis_other_entity ||= FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital #{SecureRandom.hex(2)}")
  end
end
World(DashboardWidgetInlineSettingsSteps)

# --- Icon and popup (browser) ---------------------------------------------------------------------------------

Then('every widget on the page should have a settings icon') do
  # Counted with retries: after the first save on defaults the page refreshes underneath the check (H5)
  wis_eventually do
    containers = all(".dashboard-widget-container", visible: :all).size
    icons = all(".dashboard-widget-container > .widget-settings-btn", visible: :all).size
    containers.positive? && containers == icons
  rescue Capybara::Playwright::Node::StaleReferenceError
    false
  end
end

Then('no widget should have a settings icon') do
  expect(page).to have_no_css(".widget-settings-btn", visible: :all)
end

When('I point at the {string} widget') do |widget_name|
  wis_container(widget_name).hover
end

# H1 — the icon fades in on hover
Then('the settings icon of the {string} widget should be visible') do |widget_name|
  id = wis_container(widget_name)[:id]
  wis_eventually(3) { evaluate_script("getComputedStyle(document.querySelector('##{id} > .widget-settings-btn')).opacity") == "1" }
end

When('I open the settings of the {string} widget') do |widget_name|
  container = wis_container(widget_name)
  container.hover
  container.find(".widget-settings-btn").click
  expect(page).to have_css(".widget-settings-panel.show turbo-frame#widget_settings form")
end

Then('the settings popup should be titled {string}') do |title|
  expect(wis_modal).to have_css(".offcanvas-title", text: title)
end

Then('the settings popup should show {string} as {string}') do |label, value|
  expect(wis_field(label).value).to eq(value)
end

Then('the settings popup should say {string}') do |text|
  expect(wis_modal).to have_text(text)
end

When('I set {string} to {string} in the settings popup') do |label, value|
  field = wis_field(label)
  if field.tag_name == "select"
    field.find("option", text: value, exact_text: true).select_option
  else
    field.set(value)
  end
end

When('I click {string} in the settings popup') do |button|
  wis_modal.click_button(button)
end

When('I close the settings popup') do
  wis_modal.find(".btn-close").click
end

When('I press Escape') do
  page.driver.with_playwright_page { |playwright_page| playwright_page.keyboard.press("Escape") }
end

Then('the settings popup should be closed') do
  expect(page).to have_no_css(".widget-settings-panel.show")
end

# --- Saved records ------------------------------------------------------------------------------------------

Then('the saved settings of the {string} widget on the {string} should be {string}') do |widget_name, dashboard_name, metadata|
  expected = wis_args(metadata)
  wis_eventually { wis_widget(widget_name, dashboard_name).reload.metadata_args == expected }
end

Then('the saved size of the {string} widget on the {string} should be {string}') do |widget_name, dashboard_name, size|
  wis_eventually { wis_widget(widget_name, dashboard_name).reload.size == size }
end

Then('the {string} should have {int} saved widgets: {string}') do |dashboard_name, count, names|
  rows = DashboardWidget.where(entity_id: @user.entity_id, dashboard_name:, name: "Default").order(:position)
  expect(rows.count).to eq(count)
  expect(rows.pluck(:widget_name).join(", ")).to eq(names)
end

# H5, E5, E6 — the saved set is exactly the catalogue defaults, once, in order
Then('the {string} should have its default widgets saved once, in order') do |dashboard_name|
  rows = DashboardWidget.where(entity_id: @user.entity_id, dashboard_name:, name: "Default").order(:position)
  expect(rows.pluck(:widget_name)).to eq(DashboardWidget.default_widgets_for(dashboard_name).map(&:widget_name))
  expect(rows.pluck(:position)).to eq((1..rows.count).to_a)
end

# --- Direct requests (rack_test) ----------------------------------------------------------------------------

When('I save the settings {string} with size {string} for the default {string} widget on the {string}') do |metadata, size, widget_name, dashboard_name|
  page.driver.submit :patch, save_settings_dashboard_widgets_path,
                     { dashboard_name:, layout: "Default", widget_name:, dashboard_widget: { metadata:, size: } }
end

When('I save the settings {string} with size {string} for the {string} widget on the {string}') do |metadata, size, widget_name, dashboard_name|
  page.driver.submit :patch, save_settings_dashboard_widgets_path,
                     { widget_id: wis_widget(widget_name, dashboard_name).id, dashboard_widget: { metadata:, size: } }
end

# X7 — fields the popup never sends are ignored
When('I save the settings {string} with size {string} for the {string} widget on the {string} with extra fields') do |metadata, size, widget_name, dashboard_name|
  page.driver.submit :patch, save_settings_dashboard_widgets_path,
                     { widget_id: wis_widget(widget_name, dashboard_name).id,
                       dashboard_widget: { metadata:, size:, entity_id: wis_other_entity.id, widget_name: "Notes",
                                           dashboard_name: "Ops Dashboard", name: "Hacked" } }
end

Then('the settings save should be refused with {string}') do |message|
  expect(page.status_code).to eq(422)
  expect(page).to have_text(message)
end

When('I request the settings of the {string} widget on the {string}') do |widget_name, dashboard_name|
  visit settings_dashboard_widgets_path(widget_id: wis_widget(widget_name, dashboard_name).id)
end

When('I request the settings of the default {string} widget on the {string}') do |widget_name, dashboard_name|
  visit settings_dashboard_widgets_path(dashboard_name:, layout: "Default", widget_name:)
end

Then('the settings request should be refused') do
  expect(page).to have_no_css("form[action='#{save_settings_dashboard_widgets_path}']")
end

Then('no widget should be saved for the {string}') do |dashboard_name|
  expect(DashboardWidget.where(dashboard_name:).count).to eq(0)
end

Then('the {string} widget on the {string} should still be my firm\'s, unchanged but for its settings {string} and size {string}') do |widget_name, dashboard_name, metadata, size|
  widget = wis_widget(widget_name, dashboard_name).reload
  expect([widget.entity_id, widget.widget_name, widget.dashboard_name, widget.name]).to eq([@user.entity_id, widget_name, dashboard_name, "Default"])
  expect(widget.metadata_args).to eq(wis_args(metadata))
  expect(widget.size).to eq(size)
end

# --- Other firms and roles ----------------------------------------------------------------------------------

Given('I am acting as an investor') do
  @user.add_role(:investor)
  @user.update!(curr_role: "investor")
end

Given('another firm has a saved {string} widget on the {string} with settings {string}') do |widget_name, dashboard_name, metadata|
  @wis_other_widget = DashboardWidget.create!(entity_id: wis_other_entity.id, dashboard_name:, name: "Default", widget_name:,
                                              size: "XL", tags: widget_name, enabled: true, position: 1, metadata:)
end

When("I request the settings of the other firm's widget") do
  visit settings_dashboard_widgets_path(widget_id: @wis_other_widget.id)
end

When("I save the settings {string} with size {string} for the other firm's widget") do |metadata, size|
  page.driver.submit :patch, save_settings_dashboard_widgets_path, { widget_id: @wis_other_widget.id, dashboard_widget: { metadata:, size: } }
end

Then("the other firm's widget should still have settings {string} and size {string}") do |metadata, size|
  @wis_other_widget.reload
  expect(@wis_other_widget.metadata_args).to eq(wis_args(metadata))
  expect(@wis_other_widget.size).to eq(size)
end

# --- One-widget reload (phase 2) ----------------------------------------------------------------------------

# H3 — a mark on a widget's frame survives only if that widget (and the page) is not reloaded
When('I mark the {string} widget') do |widget_name|
  id = wis_container(widget_name)[:id]
  execute_script("document.getElementById('dashboard_widget_#{id}').dataset.testMarker = 'kept'")
end

Then('the {string} widget should not have been reloaded') do |widget_name|
  id = wis_container(widget_name)[:id]
  expect(page).to have_css("#dashboard_widget_#{id}[data-test-marker='kept']", visible: :all)
end

Then('a saved message should say {string}') do |message|
  expect(page).to have_css("[data-widget-settings-toast]", text: message)
end

# H4 — the container takes the size's column class in the same refresh
Then('the {string} widget should take the {string} column') do |widget_name, css_class|
  wis_eventually { wis_container(widget_name)[:class].split.include?(css_class) }
end

Then('Valuation Freshness should list {int} companies') do |count|
  within(wis_container("Valuation Freshness")) { expect(page).to have_css("tbody tr[data-company]", count:) }
end

Then('Valuation Freshness should list only {string}') do |company|
  within(wis_container("Valuation Freshness")) do
    expect(page).to have_css("tbody tr[data-company='#{company}']")
    expect(page).to have_css("tbody tr[data-company]", count: 1)
  end
end

# H6 — the Aggregated Portfolio Dashboard filtered to one company by name
When('I open the stakeholders portfolio dashboard filtered to {string}') do |company|
  visit(investors_path(multi_portfolio_dashboard: true, fund_ids: [@fund.id], q: { investor_name_eq: company }))
end

# E7 — the browser asks for reduced motion
Given('my browser asks for reduced motion') do
  page.driver.with_playwright_page { |playwright_page| playwright_page.emulate_media(reducedMotion: "reduce") }
end

Then('the {string} widget should not be highlighted') do |widget_name|
  expect(wis_container(widget_name)[:class].split).not_to include("widget-updated")
end

# E8 — a request for a widget key that is not on the page draws no widget
When('I open the {string} of fund {string} for the widget {string}') do |dashboard_name, fund_name, key|
  visit(dashboard_fund_path(lp_fund(fund_name), dashboard_name:, only_widget: key))
end

Then('the page should show no dashboard widgets') do
  expect(page.status_code).to eq(200)
  expect(page).to have_no_css(".dashboard-widget-container", visible: :all)
end
