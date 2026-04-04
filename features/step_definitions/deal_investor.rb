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
  visit(deal_path(@deal, grid_view: true, kanban: true))

  @deal.deal_investors.each do |deal_investor|
    within("#deal_investor_#{deal_investor.id}") do
      expect(page).to have_content(deal_investor.investor_name)
      expect(page).to have_content(money_to_currency(deal_investor.primary_amount))
      expect(page).to have_content(money_to_currency(deal_investor.secondary_investment))
      expect(page).to have_content(money_to_currency(deal_investor.pre_money_valuation))
    end
  end
end

Given('I should see the deal stages in the deal details page') do
  @deal.deal_investors.each do |deal_investor|
    within("#deal_investor_#{deal_investor.id}") do
      deal_investor.deal_activities.each do |act|
        within("#deal_activity_#{act.id}") do
          expect(page).to have_content(act.completed_status)
        end
      end
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

  # 3. Simulate clicks to open dropdown as per user instruction:
  # "double click to enable inline editing, then click to open and then click to select Complete"
  target = cell.all(".badge").first || cell

  # 1. Double click to enable inline editing (as per user instruction)
  target.double_click

  # 2. Find the ag-grid select editor wrapper (it's not a native select)
  # Based on the provided HTML, it has class 'ag-picker-field-wrapper'
  picker_wrapper = cell.find(".ag-picker-field-wrapper", wait: 5)

  # 3. Click the wrapper to open the dropdown list
  picker_wrapper.click
  sleep 0.5

  # 4. Click "Complete" from the dropdown list
  # ag-grid portals these to an .ag-popup container
  begin
    # Search for the "Complete" option in common ag-grid popup classes
    dropdown_item = find(".ag-popup .ag-virtual-list-item, .ag-popup .ag-select-list-item, .ag-popup [role='option']", text: "Complete", wait: 5)
    dropdown_item.click
  rescue Capybara::ElementNotFound
    # Fallback: find any element with text "Complete" inside a popup
    find(".ag-popup", wait: 2).find("*", text: "Complete", match: :prefer_exact).click
  end

  # Wait for the dropdown popup to disappear
  expect(page).to have_no_selector(".ag-popup", wait: 5)

  # Only press Enter if the row is still in edit mode
  page.send_keys(:enter) if page.has_selector?(".ag-row-editing", wait: 1)

  # Wait for the editor to close completely
  expect(page).to have_no_selector(".ag-row-editing", wait: 5)

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
    # Wait for ag-grid
    expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 10)

    @deal.deal_investors.each do |deal_investor|
      # Investor name is pinned to the left
      selector = ".ag-pinned-left-cols-container .ag-row[row-id='deal_investor_#{deal_investor.id}']"
      expect(page).to have_selector(selector)
      within(selector) do
        expect(page).to have_content(deal_investor.investor_name)
      end
    end
  elsif page.has_selector?("#deals_list_grid", wait: 5)
    # If we don't expect to see them, the grid might be missing or empty
    @deal.deal_investors.each do |deal_investor|
      expect(page).not_to have_selector(".ag-row[row-id='deal_investor_#{deal_investor.id}']")
    end
  else
    # Grid missing entirely (possibly due to authorization redirect)
    expect(page).not_to have_selector(".ag-row")
  end
end
