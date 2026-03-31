Given('Im logged in as user {string}') do |first_name|
  @user ||= User.find_by(first_name: first_name)
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given('there is a RatioFormula for the fund {string} with {string}') do |fund_name, args|
  fund = Fund.find_by(name: fund_name)
  @ratio_formula = FactoryBot.build(:ratio_formula, fund: fund, entity: fund.entity)
  key_values(@ratio_formula, args)
  @ratio_formula.save!
end

Given('there is an AccountEntry {string} for the fund') do |args|
  @account_entry = FactoryBot.build(:account_entry, fund: @fund, entity: @fund.entity)
  key_values(@account_entry, args)
  @account_entry.save!
end

Then('the FundRatio {string} should be different from a computation without the formula') do |ratio_name|
  # This is a bit complex for a simple cucumber test, but we want to verify the impact
  ratio_with_formula = FundRatio.find_by(name: ratio_name, owner: @fund, end_date: @fund_ratio_date).value

  # Temporarily disable formula and recompute
  @ratio_formula.update!(deleted_at: Time.now)

  FundRatiosJob.perform_now(@fund.id, nil, @fund_ratio_date, @user.id, true)

  ratio_without_formula = FundRatio.find_by(name: ratio_name, owner: @fund, end_date: @fund_ratio_date).value

  expect(ratio_with_formula).not_to eq(ratio_without_formula)

  # Restore
  @ratio_formula.update!(deleted_at: nil)
end

Given('there is a simple commitment and investment for the fund') do
  # Create a portfolio company entity (startup)
  @startup_entity = FactoryBot.create(:entity, entity_type: 'Startup', name: 'Startup Entity')

  # Create a portfolio company investor record
  @portfolio_company = FactoryBot.create(:investor,
                                         entity: @entity,
                                         investor_entity: @startup_entity,
                                         category: 'Portfolio Company',
                                         investor_name: 'Test Startup')

  # Create an instrument
  @instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company, name: 'Equity')

  # Create a commitment
  @commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @entity, folio_id: 'FOLIO1', commitment_date: '2023-01-01')

  # Create an investment (Buy)
  @pi = FactoryBot.create(:portfolio_investment,
                          fund: @fund,
                          entity: @entity,
                          portfolio_company: @portfolio_company,
                          investment_instrument: @instrument,
                          investment_date: '2023-01-01',
                          amount_cents: 1_000_000,
                          base_amount_cents: 1_000_000,
                          quantity: 100)

  # Setup valuation for the end date to have FMV
  FactoryBot.create(:valuation, owner: @portfolio_company, investment_instrument: @instrument, valuation_date: '2024-03-31', per_share_value_cents: 20_000, entity: @entity)
end

Given('I go to the fund show page for {string}') do |fund_name|
  @fund = Fund.find_by(name: fund_name)
  visit fund_path(@fund)
end

When('I click link {string}') do |text|
  # Try finding it normally first
  begin
    click_on(text)
  rescue Capybara::ElementNotFound
    # If not found or obscured (like in a dropdown), try forcing a click or finding specifically
    begin
      find('a, button, span', text: text, match: :first, visible: :all).click
    rescue StandardError
      # Last resort: execute JS click
      page.execute_script("Array.from(document.querySelectorAll('a, button, span')).find(el => el.textContent.trim() === '#{text}')?.click()")
    end
  end
  sleep(0.5)
end

When('I select option {string} from {string}') do |value, field|
  select(value, from: field)
rescue Capybara::ElementNotFound
  # Try Select2
  # Find the label and its associated select, or use the name directly
  select_element = begin
    find("select[name='#{field}']", visible: false, match: :first)
  rescue StandardError
    find_field(field, visible: false, match: :first)
  end

  # Select2 multiple or single
  container = select_element.sibling('.select2-container')
  container.find('.select2-selection').click

  # Wait for dropdown and select option
  find('.select2-results__option', text: value).click
end
