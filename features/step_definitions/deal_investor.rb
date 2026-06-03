include ActionView::Helpers::NumberHelper
include CurrencyHelper

When('I create a new deal investor {string}') do |arg1|
  @deal_investor = FactoryBot.build(:deal_investor)
  @deal_investor.investor_name = @deal_investor.investor.investor_name
  key_values(@deal_investor, arg1)
  puts "\n####DealInvestor####\n"
  puts @deal_investor.to_json

  click_on("Add Investor")

  select(@deal_investor.investor_name, from: "deal_investor_investor_id")
  fill_in('deal_investor_primary_amount', with: @deal_investor.primary_amount)
  fill_in('deal_investor_secondary_investment', with: @deal_investor.secondary_investment)
  fill_in('deal_investor_pre_money_valuation', with: @deal_investor.pre_money_valuation)

  click_on("Save")
end

Then('a deal investor should be created') do
  @created = DealInvestor.last
  @created.deal_id.should
  @deal.id
  @created.investor_id.should
  @deal_investor.investor_id
  @created.primary_amount.should
  @deal_investor.primary_amount
  @created.secondary_investment.should
  @deal_investor.secondary_investment
  @created.entity_id.should
  @deal.entity_id
  @deal_investor = @created
end

Then('I should see the deal investor details on the details page') do
  visit(deal_investor_path(@deal_investor.id))
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(@deal_investor.investor_name)
  expect(page).to have_content(money_to_currency(@deal_investor.primary_amount))
  expect(page).to have_content(money_to_currency(@deal_investor.secondary_investment))
  expect(page).to have_content(money_to_currency(@deal_investor.pre_money_valuation))
  expect(page).to have_content(@deal_investor.entity_name)
end

Then('I should see the deal investor in all deal investors page') do
  visit("/deal_investors")
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(@deal_investor.investor_name)
  expect(page).to have_content(money_to_currency(@deal_investor.primary_amount))
  expect(page).to have_content(money_to_currency(@deal_investor.secondary_investment))
  expect(page).to have_content(money_to_currency(@deal_investor.pre_money_valuation))
  # expect(page).to have_content(@deal_investor.entity_name)
end

Given('there are {string} deal_investors for the deal') do |arg|
  (1..arg.to_i).each do |i|
    FactoryBot.create(:deal_investor, deal: @deal, entity: @deal.entity,
                                      status: "Active", investor: Investor.find(i))
  end
  @deal.reload
end

Given('I should see the deal investors in the deal details page') do
  visit(deal_path(@deal))
  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)
  expect(page).to have_selector("#deals_list_grid .ag-row", wait: 20)

  @deal.deal_investors.each do |deal_investor|
    row_id = "deal_investor_#{deal_investor.id}"
    # Verify the row exists via the center container (avoids pinned-cols ambiguity)
    expect(page).to have_selector("#deals_list_grid .ag-center-cols-container .ag-row[row-id='#{row_id}']", wait: 10)
    # Investor name may be in a pinned column container — check any row with this row-id
    expect(page).to have_selector("#deals_list_grid .ag-row[row-id='#{row_id}']", text: deal_investor.investor_name, wait: 10)
  end
end

Given('I should see the deal stages in the deal details page') do
  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)
  expect(page).to have_selector("#deals_list_grid .ag-row", wait: 20)

  @deal.deal_investors.each do |deal_investor|
    row_id = "deal_investor_#{deal_investor.id}"
    # Verify the row exists in the center container (avoids pinned-cols ambiguity)
    expect(page).to have_selector("#deals_list_grid .ag-center-cols-container .ag-row[row-id='#{row_id}']", wait: 10)

    deal_investor.deal_activities.each do |act|
      # Scroll activity column into view to defeat AG Grid column virtualization
      page.execute_script(<<~JS)
        if (window.DealsGrid && window.DealsGrid.gridOptions && window.DealsGrid.gridOptions.api) {
          window.DealsGrid.gridOptions.api.ensureColumnVisible('activity_#{act.template_id}');
        }
      JS
      expected = act.Complete? ? "Complete" : "Incomplete"
      # Check in the full grid — each act.id is unique so no false matches across rows
      expect(page).to have_css("#deals_list_grid .activity-badge[data-activity-id='#{act.id}'][data-activity-status='#{expected}']", wait: 5)
    end
  end
end

Given('the deal activites are completed') do
  @deal.deal_activities.update_all(completed: true)
  @deal.reload
end

Given('I complete an activity') do
  @deal_activity = @deal.deal_activities.where.not(deal_investor_id: nil).first

  # 1. Wait for ag-grid to be completely mounted
  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)

  # Wait for rows to populate
  expect(page).to have_selector("#deals_list_grid .ag-row", wait: 20)

  # 2. Triggering the Inline Editor (UI Simulation)
  # Scroll cell into view using grid API (safer than native scroll for ag-grid)
  page.execute_script(%{
    const gridApi = window.DealsGrid.gridOptions.api;
    const rowId = 'deal_investor_#{@deal_activity.deal_investor_id}';
    const rowNode = gridApi.getRowNode(rowId);
    if (rowNode) {
      gridApi.ensureNodeVisible(rowNode);
      gridApi.ensureColumnVisible('activity_#{@deal_activity.template_id}');
    } else {
      window.rowNodeMissing = true;
    }
  })

  raise "Row node not found in ag-grid for deal_investor_#{@deal_activity.deal_investor_id}" if page.evaluate_script("window.rowNodeMissing")

  # Find the specific cell
  row_selector = ".ag-center-cols-container .ag-row[row-id='deal_investor_#{@deal_activity.deal_investor_id}']"
  col_selector = "[col-id='activity_#{@deal_activity.template_id}']"
  cell = find("#{row_selector} #{col_selector}")

  # Click the activity badge to open the floating menu (new floating-menu UI)
  badge = cell.find(".activity-badge", wait: 5)
  badge.click

  # Wait for the floating menu to appear and click "Complete"
  floating_menu = find("#deals-activity-floating-menu", wait: 5)
  floating_menu.find("[data-status='complete']", wait: 5).click

  # Wait for the floating menu to hide
  expect(page).to have_no_selector("#deals-activity-floating-menu[style*='display: block']", wait: 5)

  # Wait for the UI to reflect the change visually
  within(row_selector) do
    expect(page).to have_content("Complete", wait: 10)
  end
end

Then('the activity must be completed') do
  row_selector = ".ag-center-cols-container .ag-row[row-id='deal_investor_#{@deal_activity.deal_investor_id}']"
  col_selector = "[col-id='activity_#{@deal_activity.template_id}']"

  within(row_selector) do
    within(col_selector) do
      expect(page).to have_content("Complete")
      expect(page).to have_selector(".bg-success-light")
    end
  end

  # Wait for the database to be updated (the fetch call in JS is async)
  max_wait = 10
  start_time = Time.now
  loop do
    @deal_activity.reload
    break if @deal_activity.status == "Complete"
    raise "Activity status did not update to 'Complete' in database within #{max_wait}s. Current: #{@deal_activity.status}" if Time.now - start_time > max_wait

    sleep 0.5
  end
end

Given('there is a deal investor for the last investor') do
  inv = Investor.last
  @deal_investor = FactoryBot.create(:deal_investor, investor: inv, entity_id: inv.entity_id, deal: @deal)
end

Given('there is a deal investor with name {string}') do |name|
  inv = Investor.find_by(investor_name: name)
  @deal_investor = FactoryBot.create(:deal_investor, investor: inv, entity_id: inv.entity_id, deal: @deal)
end

When('I view the deal investor details') do
  visit(deal_investor_path(@deal_investor))
end

Given('I am {string} employee access to the deal_investors') do |given|
  if %w[given yes].include?(given)
    DealInvestor.all.each do |di|
      @access_right = AccessRight.create!(entity_id: di.entity_id, owner: di, user_id: @user.id)
      puts "\n####AccessRight####\n"
      puts @access_right.to_json
    end
  end
  @user.reload
end

Then('I {string} see the deal investors in the deal details page') do |should|
  visit(deal_path(@deal, list_view: true))

  if should == "true"
    # Verify the grid container is rendered server-side (proves authorization passed).
    # AG Grid is loaded from an external CDN which may not be available in the test
    # environment, so we check for the server-rendered container rather than .ag-root-wrapper.
    expect(page).to have_selector("#deals_list_grid", wait: 10),
      "Expected #deals_list_grid to be present on #{current_url}"
  else
    # Employee has no access — grid container should not be rendered OR page redirected
    expect(page).not_to have_selector("#deals_list_grid", wait: 5)
  end
end
