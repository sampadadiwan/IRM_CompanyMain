# Steps for features/core/dashboard_insight_widgets_common.feature
# (openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#1-rules-every-widget-follows--phase-1)

# H1 — the New Widget form carries every dashboard's widget types as JSON (widget_options_json); the widget must be
# listed under exactly the named dashboards
Then('the new widget form should offer {string} only on {string}') do |widget_name, dashboards|
  # Read the per-dashboard widget lists the form's Stimulus controller fills the Widget Type select from
  options = JSON.parse(find("#widget_options_json", visible: :all).value)
  # The dashboards whose list holds this widget, compared with the expected ones (order-free)
  offered_on = options.select { |_dashboard, names| names.include?(widget_name) }.keys
  expect(offered_on).to match_array(dashboards.split(",").map(&:strip))
end

# X2, X9 — the dashboard renders the widget's container, but an internal widget's partial renders nothing inside it
Then('the {string} insight widget should not be rendered') do |widget_name|
  # The page wraps each widget in <div id="<widget_name parameterized>_<position>">
  prefix = widget_name.parameterize.underscore
  containers = all("[id^='#{prefix}_']", visible: :all)
  expect(containers).not_to be_empty
  containers.each { |container| expect(container).to have_no_css(".card", visible: :all) }
end

Then('the {string} insight widget should be rendered') do |widget_name|
  prefix = widget_name.parameterize.underscore
  expect(page).to have_css("[id^='#{prefix}_'] .card", visible: :all)
end
