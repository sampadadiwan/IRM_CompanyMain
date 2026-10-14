# Steps for features/core/lp_gp_picker.feature - the LP dashboard top-bar GP picker
# (entities/_vc_dashboard.html.erb + gp_switcher_controller.js). The picker <select name="gp_entity_id">
# is rendered hidden in the dashboard and moved into #topbar_gp_dropdown by the Stimulus controller.
# Setup reuses investor_notice_carousel_steps.rb: @entity is the first GP, @second_gp_entity /
# @second_investor / @second_investor_access the second one.

Given('the second GP entity has a fund {string} shared with the investor') do |fund_name|
  @second_gp_fund = FactoryBot.create(:fund, entity_id: @second_gp_entity.id, name: fund_name)
  # The same fund-level right "the investors are added to the fund" grants, for the LP's investor row
  AccessRight.create!(owner: @second_gp_fund, access_type: "Fund", metadata: "Investor",
                      access_to_investor_id: @second_investor.id, entity: @second_gp_entity)
end

When('I pick the GP {string} in the GP picker') do |gp_name|
  # Changing the select fires gp-switcher#switch, which submits the form into vc_dashboard_frame
  within("#topbar_gp_dropdown") { select(gp_name, from: "gp_entity_id") }
end

Then('the GP picker should show {string}') do |gp_name|
  within("#topbar_gp_dropdown") do
    expect(page).to have_select("gp_entity_id", selected: gp_name, wait: 15)
  end
end

Then('the page URL should carry the GP {string}') do |gp_name|
  gp = Entity.find_by!(name: gp_name)
  # turbo_action "advance" writes the frame's URL into the address bar
  expect(page).to have_current_path(/[?&]gp_entity_id=#{gp.id}(&|\z)/, wait: 15)
end

Then('I should see the banner for the GP {string}') do |gp_name|
  expect(page).to have_css("#vc_dashboard_frame", text: "You are currently viewing data for #{gp_name}.", wait: 15)
end

Then('I should not see the banner for the GP {string}') do |gp_name|
  expect(page).to have_no_css("#vc_dashboard_frame", text: "You are currently viewing data for #{gp_name}.")
end

When('I open the fund page of {string}') do |fund_name|
  fund = Fund.find_by!(name: fund_name)
  visit(fund_path(fund))
  expect(page).to have_content(fund_name, wait: 15)
end

When('I go back in the browser') do
  page.go_back
end

When('I click Dashboard in the sidebar') do
  # The sidebar Dashboard link is a plain /entities/dashboard - no gp_entity_id on it
  find("#sidebarnav a.sidebar-link[href='/entities/dashboard']").click
  expect(page).to have_current_path("/entities/dashboard", wait: 15)
end

When("the investor user's access to the GP {string} is unapproved") do |gp_name|
  gp = Entity.find_by!(name: gp_name)
  InvestorAccess.where(user_id: @investor_user.id, entity_id: gp.id).find_each { |ia| ia.update!(approved: false) }
end

When("the investor user's access to the GP {string} is revoked") do |gp_name|
  gp = Entity.find_by!(name: gp_name)
  InvestorAccess.where(user_id: @investor_user.id, entity_id: gp.id).find_each(&:destroy!)
end
