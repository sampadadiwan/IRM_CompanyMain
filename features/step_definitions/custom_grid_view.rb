Given('I am at the form type page') do
  visit("/form_types")
  #sleep(0.5)
end

Given('I am at the reports page') do
  visit("/reports")
  #sleep(0.5)
end

When('I create a report and custom grid view for {string}') do |report|
  select("Portfolio Investments", from: 'url')
  #sleep(0.5)
  find('a[aria-label="Save Report"]').click
  #sleep(0.5)
  fill_in('report_name', with: "PI Report")
  fill_in('report_category', with: "Portfolio Investments")
  click_on('Save')
  #sleep(0.5)
  visit("/reports")
  #sleep(0.5)
  find('.more-options.text-dark').click
  click_link("Configure Grid")
  #sleep(0.5)
end

When('I create a form type and custom grid view for {string}') do |form_type|
  FormType.where(name: form_type).destroy_all
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select(form_type)
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')
  @form_type = FormType.where(name: form_type).last
  #sleep(1)
end

When('I create a derived field {string}') do |form_type|
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select(form_type)
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')

  # Configure Grids shows the shared columns editor (grid-columns-inline-settings D19, D20): the derived field
  # is added in its "Add derived field" box, then the whole list is saved
  find("[data-grid-columns-derived] summary").click
  find("[data-grid-columns-form-target='derivedLabel']").fill_in(with: "PI's Instrument")
  find("[data-grid-columns-form-target='derivedKey']").fill_in(with: "instrument_name")
  find("[data-grid-columns-form-target='derivedType']").select("String")
  find("[data-grid-columns-add-derived]").click
  # The old form put it at position 1; the editor adds it last, so drag it to the top (an AG grid draws only the
  # columns in view)
  derived = "//li[@data-grid-columns-row][@data-derived='true']"
  first = "(//ul[@data-grid-columns-form-target='list']/li[@data-grid-columns-row])[1]"
  page.driver.with_playwright_page do |pw|
    pw.locator("xpath=#{derived}").drag_to(pw.locator("xpath=#{first}"), targetPosition: { x: 40, y: 3 })
  end
  grid_columns_save_full_page
end

# Deletes a saved column on Configure Grids by its key (with or without a "; css" suffix), through the popup
# An exact key first; else, as the old page's `contains(@class, 'column_<key>')` did, the first key containing it
def grid_columns_delete_row(key)
  exact = "//li[@data-grid-columns-row][@data-key='#{key}' or starts-with(@data-key, '#{key};')]"
  xpath = page.has_xpath?(exact, wait: 5) ? exact : "(//li[@data-grid-columns-row][contains(@data-key, '#{key}')])[1]"
  row = find(:xpath, xpath)
  row_id = row["data-id"]
  row.find("[data-grid-columns-delete]").click
  click_on("Proceed")
  expect(page).to have_no_css("li[data-grid-columns-row][data-id='#{row_id}']", wait: 30)
end

# Headings of the tables on the page, whole text without the sort arrows
def grid_heading_texts
  all("thead th").map { |th| th.text.gsub(/[▲▼]/, "").squish }
end

# Saves the shared columns editor on Configure Grids and waits for the page to refresh in place
def grid_columns_save_full_page
  find("[data-grid-columns-save]").click
  expect(page).to have_css("[data-grid-columns-form-target='list']", wait: 30)
  expect(page).to have_no_css("[data-grid-columns-save][disabled]", wait: 30)
end

When("I select each option and click Add") do
  # Every column offered in "Add a column" goes into the list (the option leaves the list once added), then Save
  find("#grid_columns_add", visible: :all, wait: 30)
  loop do
    added = page.evaluate_script(<<~JS)
      (() => {
        const sel = document.querySelector("#grid_columns_add");
        const opt = Array.from(sel.options).find((o) => o.value);
        if (!opt) return false;
        sel.value = opt.value;
        sel.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      })()
    JS
    break unless added
  end
  grid_columns_save_full_page
end

Given('I visit Investor Page and find 6 columns in the grid') do
  visit('/investors')
  @expected_columns = %w[Stakeholder Tags Category Access]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit PortfolioInvestment Page and find 6 columns in the grid') do
  visit('/portfolio_investments')
  @expected_columns = ["Portfolio Company", "Investment Date", "Amount", "Quantity", "Cost Per Share", "FMV", "FIFO Cost", "Notes"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit PortfolioInvestment Page from reports') do
  visit(Report.first.url)
  @expected_columns = ["Portfolio Company", "Investment Date", "Amount", "Quantity", "Cost Per Share", "FMV", "FIFO Cost", "Notes"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit AggregatePortfolioInvestment Page and find 6 columns in the grid') do
  visit('/aggregate_portfolio_investments')
  @expected_columns = ["Portfolio Company", "Instrument", "Net Bought Amount", "Sold Amount", "Current Quantity", "Fmv", "Avg Cost / Share"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit CapitalCommitment Page and find 6 columns in the grid') do
  visit('/capital_commitments')
  @expected_columns = ["Type", "Folio", "Stakeholder", "Investing", "Entity", "Unit", "Type", "Committed", "Called", "Collected", "Distributed"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit InvestorKyc Page and find 6 columns in the grid') do
  visit('/investor_kycs')
  @expected_columns = ["Stakeholder", "Investing", "Entity", "Type", "Kyc", "Verified", "Expired"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit FundUnitSetting Page and find columns in the grid') do
  visit('/fund_unit_settings')
  @expected_columns = ["Class/Series", "Management Fee %", "Setup Fee %", "Carry", "ISIN"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I visit Custom Grid View page and uncheck {string}') do |column_name|
  visit "/grid_view_preferences/configure_grids?owner_id=#{@form_type.id}&owner_type=FormType"
  # D19 — the saved column's Delete on the shared editor, then the confirmation popup
  grid_columns_delete_row(column_name.downcase)
end

When('I visit Report Custom Grid View page and uncheck {string}') do |column_name|
  report = Report.first
  visit '/grid_view_preferences/configure_grids?owner_id=1&owner_type=Report'
  # D19 — the saved column's Delete on the shared editor, then the confirmation popup
  grid_columns_delete_row(column_name.downcase)
end


Given('I should not find {string} column in the Investor Grid') do |column_name|
  visit('/investors')
  #sleep(0.25)

  column_title = column_name.capitalize

  # The whole heading (not part of one: "Tracking Amount" is not the "Amount" column)
  expect(grid_heading_texts).not_to include(column_title)
end

Given('I should not find {string} column in the Portfolio Investment Grid') do |column_name|
  visit('/investors')
  #sleep(0.25)

  column_title = column_name.capitalize

  # The whole heading (not part of one: "Tracking Amount" is not the "Amount" column)
  expect(grid_heading_texts).not_to include(column_title)
end

Given('I should not find {string} column in the Report PI Grid') do |column_name|
  visit(Report.first.url)
  #sleep(0.25)
  column_title = column_name.capitalize

  # The whole heading (not part of one: "Tracking Amount" is not the "Amount" column)
  expect(grid_heading_texts).not_to include(column_title)
end

When("I visit Portfolio Investment AG Grid and find the derived field") do
  visit portfolio_investments_path(filter: true)
  check('ag_grid')
  find('button.search-button[aria-label="Search"]').click
  expect(page).to have_content("PI's Instrument")
end


When('I visit {string} Page and find columns in the grid') do |class_name|
  page_url = "/#{class_name.underscore.pluralize}"
  visit(page_url)
  # @expected_columns = class_name::STANDARD_COLUMNS.keys.compact
  @expected_columns =
  case class_name.to_s
  when 'CapitalRemittance'
    ["Stakeholder", "Folio No", "Status", "Verified", "Due Amount", "Collected Amount", "Payment Date"]
  when 'CapitalCall'
    ["Name", "Due Date", "Call Amount", "Collected Amount", "Due Amount", "Approved"]
  when 'FundReport'
    ["Id", "Name", "Name Of Scheme", "Start Date", "End Date"]
  when "FundRatio"
    ["For", "Type", "Name", "Display Value", "On", "Scenario"]
  when "KpiReport"
    ["As Of", "Period", "Notes", "User", "For"]
  when "Offer"
     ["Investor", "User", "Quantity", "Price", "Allocation Quantity", "Allocation Amount", "Approved", "Verified", "Updated At"]
  end

  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I should not find {string} column in the {string} Grid') do |column, class_name|
  visit("/#{class_name.underscore.pluralize}")
  #sleep(0.25)
  column_title = column.titleize

  # The whole heading (not part of one: "Tracking Amount" is not the "Amount" column)
  expect(grid_heading_texts).not_to include(column_title)
end
