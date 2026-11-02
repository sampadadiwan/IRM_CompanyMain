# Steps for features/core/dashboard_widget_menu.feature (fix-portfolio-dashboard-widgets: page and menu follow the
# enabled widgets). Worked examples: openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples

PORTCO_DASHBOARD = "Portfolio Company Dashboard".freeze
MENU_LINKS_CSS = ".dashboard-nav ul.nav-pills > li.nav-item:not(.dropdown) > a".freeze

# Rows: | widget | position | tags | tag_list | layout | enabled | show_menu |  (enabled and show_menu default to yes)
Given('the company dashboard has widgets:') do |table|
  table.hashes.each_with_index do |row, i|
    DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: PORTCO_DASHBOARD, name: row["layout"].presence || "Default",
                            widget_name: row["widget"], size: "XL", position: (row["position"].presence || (i + 1)).to_i,
                            tags: row["tags"].presence || row["widget"], tag_list: row["tag_list"].presence, display_name: true,
                            enabled: row["enabled"] != "no", show_menu: row["show_menu"] != "no")
  end
end

Given('the portfolio company has a report tagged for its dashboard') do
  Report.create!(name: "Q1 Pack", curr_role: "company_admin", entity_id: @user.entity_id, user: @user, url: "/investors", tag_list: PORTCO_DASHBOARD)
end

Given('the portfolio company has a logo') do
  Document.create!(entity_id: @portfolio_company.entity_id, owner: @portfolio_company, name: "Logo", user: @user,
                   folder: @portfolio_company.document_folder, file: File.new("public/img/logo_big.png", "r"))
end

When('I open the company page') do
  visit(dashboard_investor_path(@portfolio_company))
end

def page_widget_names
  all(".dashboard-widget-container", visible: :all).map { |container| container[:id].sub(/_\d*\z/, "") }
end

def widget_ids(names)
  names.split(",").map { |name| name.strip.parameterize(separator: "_") }
end

Then('the page should show the widgets {string}') do |names|
  expect(page).to have_css(".dashboard-widget-container")
  expect(page_widget_names).to eq(widget_ids(names))
end

Then('the page should show the default widgets') do
  expect(page).to have_css(".dashboard-widget-container")
  expect(page_widget_names).to eq(DashboardWidget::WIDGETS[PORTCO_DASHBOARD].map { |widget| widget.widget_name.parameterize(separator: "_") })
end

Then('the page should show no widgets') do
  expect(page).to have_css(".single-portfolio-dashboard")
  expect(page).to have_no_css(".dashboard-widget-container")
end

Then('the menu should list {string}') do |labels|
  expect(page).to have_css(MENU_LINKS_CSS)
  expect(all(MENU_LINKS_CSS, visible: :all).map { |link| link.text(:all).strip }).to eq(labels.split(",").map(&:strip))
end

Then('the menu should list the default widgets') do
  expect(page).to have_css(MENU_LINKS_CSS)
  defaults = DashboardWidget::WIDGETS[PORTCO_DASHBOARD].map(&:widget_name)
  expect(all(MENU_LINKS_CSS, visible: :all).map { |link| link.text(:all).strip }).to eq(defaults)
end

Then('no menu row should be shown') do
  expect(page).to have_no_css(".dashboard-nav ul.nav-pills")
  expect(page).to have_no_css(MENU_LINKS_CSS)
end

Then('the menu should have no Reports drop-down and no layout selector') do
  expect(page).to have_no_css(".dashboard-nav", text: "Reports")
  expect(page).to have_no_css(".dashboard-nav [data-controller='dashboard-selector'], .dashboard-nav select")
end

Then('the logo heading with {string} should still show') do |title|
  expect(page).to have_css(".dashboard-nav .dashboard-nav-logo")
  expect(page).to have_css(".dashboard-nav", text: title)
end

When('I click the menu link {string}') do |label|
  click_link(label, match: :first)
end

Then('the menu link {string} should lead to its widget') do |label|
  anchor = find(MENU_LINKS_CSS, text: label, visible: :all)[:href][/#(.+)\z/, 1]
  expect(anchor).to be_present
  expect(page).to have_css("##{anchor}.dashboard-widget-container")
end

# LP company page: Show Menu off on every widget of the layout
Given('Show Menu is off for every widget of the LP layout {string}') do |layout|
  DashboardWidget.where(entity_id: @user.entity_id, dashboard_name: PORTCO_DASHBOARD, name: layout).update_all(show_menu: false)
end

Then('the LP company page should have no menu row') do
  expect(page).to have_css("#lp_company_dashboard")
  expect(page).to have_no_css(".dashboard-nav ul.nav-pills")
end

# Cross portfolio dashboard (E5): enabled widgets, none with Show Menu
Given('the cross portfolio dashboard has the widget {string} with Show Menu off') do |widget|
  DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: DashboardWidget::AGGREGATED_PORTFOLIO_DASHBOARD, name: "Default",
                          widget_name: widget, size: "XL", position: 1, tags: widget, display_name: true, enabled: true, show_menu: false)
end

Then('the cross portfolio dashboard should show only the widget {string}') do |widget|
  expect(page).to have_css(".portfolio-dashboard__widgets .dashboard-widget-container")
  ids = all(".portfolio-dashboard__widgets .dashboard-widget-container", visible: :all).map { |container| container[:id].sub(/_\d*\z/, "") }
  expect(ids).to eq([widget.parameterize(separator: "_")])
end
