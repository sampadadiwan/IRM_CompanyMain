# Step definitions for the date range sanity rules (features/fund/date_range_sanity_*.feature).
# Seeding, overrides, rule evaluation and the valuation / fund ratio form steps are reused from
# validation_rules.rb; this file adds relative dates, controller-level triggers, imports and
# background-job assertions.

### Relative dates #############################################################

# The window moves with today, so scenarios name dates relative to Date.current instead of
# freezing time (travel_to interferes with @javascript sessions). Placeholders can appear anywhere
# in a step argument, including inside "key=value;key=value" strings:
#   <today>  <21 years ago>  <25 years from now>  <1 year ago>
RELATIVE_DATE_PATTERN = /<(?:today|(\d+) years? (ago|from now))>/

def expand_relative_dates(text)
  text.to_s.gsub(RELATIVE_DATE_PATTERN) do
    years = Regexp.last_match(1).to_i
    date = case Regexp.last_match(2)
           when "ago" then Date.current - years.years
           when "from now" then Date.current + years.years
           else Date.current
           end
    date.iso8601
  end
end

### Background jobs ############################################################

# Cucumber runs jobs :inline. Scenarios that assert a job was (or was not) enqueued switch to the
# :test adapter just before the action, so setup steps still run their jobs inline.
Given('background jobs are captured instead of run') do
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  @capturing_jobs = true
end

After do
  ActiveJob::Base.queue_adapter = :inline if @capturing_jobs
end

def captured_jobs(job_name)
  expect(@capturing_jobs).to be(true), "Add 'Given background jobs are captured instead of run' before the action"
  ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job].name == job_name }
end

Then('no {string} job is enqueued') do |job_name|
  jobs = captured_jobs(job_name)
  expect(jobs).to be_empty, "Expected no #{job_name} to be enqueued, found #{jobs.size}"
end

Then('a {string} job is enqueued') do |job_name|
  expect(captured_jobs(job_name)).not_to be_empty, "Expected a #{job_name} to be enqueued"
end

### Second entity ##############################################################

# Switches @entity to a fresh entity with its own portfolio company and instrument, so the next
# evaluation runs without the first entity's overrides.
Given('I switch to another entity {string} with a portfolio company') do |args|
  @entity = FactoryBot.build(:entity)
  key_values(@entity, args)
  @entity.save!
  @portfolio_company = nil
  @investment_instrument = nil
  steps %(
    Given there is an existing portfolio company ""
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  )
end

### Controller requests (logged-in browser) ####################################

# Submits a hidden form from the logged-in browser straight to the controller action, as the run
# modals do, so the session cookie goes with it and the redirect's flash renders for "Then I see".
# form.submit() skips the submit event, so Turbo does not intercept it; forgery protection is off
# in the test environment.
def submit_as_logged_in_user(method, path, params)
  # Settle on a rendered app page first: right after login the browser may still be navigating
  visit(root_path)
  expect(page).to have_css("body")
  fields = params.merge(_method: method).map { |name, value| [name.to_s, value.to_s] }
  page.execute_script(<<~JS, path, fields)
    const [action, fields] = arguments;
    const form = document.createElement("form");
    form.method = "post";
    form.action = action;
    fields.forEach(([name, value]) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.appendChild(input);
    });
    document.body.appendChild(form);
    form.submit();
  JS
end

When('I trigger the fund ratio run template {string} with end date {string}') do |name, date|
  template = FundRatioRunTemplate.find_by!(entity: @entity, name:)
  submit_as_logged_in_user(:post, trigger_one_fund_ratio_run_template_path(template), end_date: expand_relative_dates(date))
end

When('I trigger the fund ratio run templates tagged {string} with end date {string}') do |tag, date|
  submit_as_logged_in_user(:post, trigger_by_tag_fund_ratio_run_templates_path, tag:, end_date: expand_relative_dates(date))
end

When('I run allocations for the fund from {string} to {string}') do |start_date, end_date|
  @allocation_run_count = AllocationRun.where(fund_id: @fund.id).count
  submit_as_logged_in_user(:patch, allocate_fund_path(@fund), start_date: expand_relative_dates(start_date),
                                                              end_date: expand_relative_dates(end_date),
                                                              run_allocations: "1")
end

# allocation_runs is excluded from DatabaseCleaner truncation, so compare against the count
# taken before the request rather than asserting the table is empty.
Then('no allocation run is created for the fund') do
  expect(AllocationRun.where(fund_id: @fund.id).count).to eq(@allocation_run_count)
end

### Valuation import ###########################################################

# Imports the table's rows through ImportUploadJob, using a file written for the scenario. The
# table's header row is the import file's header row.
When('I import valuations') do |table|
  rows = table.raw.map { |row| row.map { |cell| expand_relative_dates(cell) } }
  @import_upload = import_rows_for("Valuation", rows)
end

def import_rows_for(import_type, rows)
  path = Rails.root.join("tmp", "date_range_sanity_#{import_type.underscore}_#{SecureRandom.hex(4)}.xlsx")
  Axlsx::Package.new do |package|
    package.workbook.add_worksheet(name: import_type) do |sheet|
      # Typed as strings so the importer parses the dates itself, exactly as for a hand-made file
      rows.each { |row| sheet.add_row(row, types: Array.new(row.size, :string)) }
    end
    package.serialize(path.to_s)
  end

  upload = ImportUpload.create!(entity: @entity, owner: @fund || @entity, import_type:, name: "Import #{import_type}",
                                user_id: @user.id, import_file: File.open(path))
  ImportUploadJob.perform_now(upload.id)
  upload.reload
ensure
  FileUtils.rm_f(path) if path
end

# Each data row of the attached results sheet, joined to one string (status and error included).
def import_result_rows(import_upload)
  expect(import_upload.import_results).to be_present, "The import has no results file"
  Tempfile.create(["import_results", ".xlsx"], binmode: true) do |tmp|
    import_upload.import_results.open { |io| tmp.write(io.read) }
    tmp.flush
    Roo::Spreadsheet.open(tmp.path).each_with_index.filter_map do |row, idx|
      row.compact.join(" ") unless idx.zero?
    end
  end
end

Then('the import has {int} processed and {int} failed row(s)') do |processed, failed|
  expect(@import_upload.processed_row_count).to eq(processed)
  expect(@import_upload.failed_row_count).to eq(failed)
end

Then('import row {int} fails with {string}') do |row_number, text|
  row = import_result_rows(@import_upload)[row_number - 1]
  expect(row).to include("Error"), "Expected row #{row_number} to fail, got: #{row}"
  expect(row).to include(expand_relative_dates(text))
end

Then('import row {int} succeeds') do |row_number|
  row = import_result_rows(@import_upload)[row_number - 1]
  expect(row).to include("Success"), "Expected row #{row_number} to succeed, got: #{row}"
end

### Assertions on rule messages ################################################

# Same as "the rule message includes", with relative-date placeholders expanded.
Then('the rule message includes the date {string}') do |text|
  steps %(Then the rule message includes "#{expand_relative_dates(text)}")
end

Then('I see the date {string}') do |text|
  steps %(Then I see "#{expand_relative_dates(text)}")
end

Then('no valuation dated {string} exists for the portfolio company') do |date|
  expect(@portfolio_company.valuations.where(valuation_date: Date.parse(expand_relative_dates(date)))).not_to exist
end

### Portfolio investments ######################################################

def build_rule_test_portfolio_investment(investment_date)
  @portfolio_company     ||= @entity.investors.portfolio_companies.last
  @investment_instrument ||= @portfolio_company.investment_instruments.last
  FactoryBot.build(:portfolio_investment, entity: @entity, fund: @fund, portfolio_company: @portfolio_company,
                                          investment_instrument: @investment_instrument, quantity: 100,
                                          investment_date: Date.parse(expand_relative_dates(investment_date)))
end

# Evaluates rules for an unsaved PortfolioInvestment, as validation_rules.rb does for other models.
When('the validation rules are evaluated for a PortfolioInvestment with {string}') do |args|
  attrs = expand_relative_dates(args).split(";").to_h { |p| p.split("=", 2) }
  record = build_rule_test_portfolio_investment(attrs["investment_date"])
  @rule_results = WithValidationRules.skip { ValidationRuleEvaluator.call(record:, entity: @entity) }
end

When('I create a portfolio investment dated {string}') do |date|
  @aggregate_count = AggregatePortfolioInvestment.count
  @valuation_count = Valuation.count
  @portfolio_investment = build_rule_test_portfolio_investment(date)
  @pi_result = PortfolioInvestmentCreate.call(portfolio_investment: @portfolio_investment)
end

# A PI saved before the date rule existed: created with the rule engine skipped, as a migration would.
Given('there is a legacy portfolio investment dated {string}') do |date|
  @portfolio_investment = build_rule_test_portfolio_investment(date)
  result = WithValidationRules.skip { PortfolioInvestmentCreate.call(portfolio_investment: @portfolio_investment) }
  raise "Failed to create legacy portfolio investment: #{result[:errors]}" if result.failure?
end

Given('there is a portfolio investment dated {string}') do |date|
  @portfolio_investment = build_rule_test_portfolio_investment(date)
  result = PortfolioInvestmentCreate.call(portfolio_investment: @portfolio_investment)
  raise "Failed to create portfolio investment: #{result[:errors]}" if result.failure?
end

# Updates one attribute through PortfolioInvestmentUpdate, as the edit form does.
When('I update the portfolio investment {string} to {string}') do |attribute, value|
  @portfolio_investment.reload.assign_attributes(attribute => expand_relative_dates(value))
  @pi_result = PortfolioInvestmentUpdate.call(portfolio_investment: @portfolio_investment)
end

Then('the portfolio investment is saved') do
  expect(@pi_result).to be_success, "Expected the save to succeed: #{@pi_result[:errors]}"
end

Then('the portfolio investment is rejected with {string}') do |text|
  expect(@pi_result).not_to be_success
  expect(@portfolio_investment.errors.full_messages.join(" ")).to include(expand_relative_dates(text))
end

Then('no aggregate portfolio investment or valuation is created') do
  expect(AggregatePortfolioInvestment.count).to eq(@aggregate_count)
  expect(Valuation.count).to eq(@valuation_count)
end

When('I import portfolio investments') do |table|
  rows = table.raw.map { |row| row.map { |cell| expand_relative_dates(cell) } }
  @import_upload = import_rows_for("PortfolioInvestment", rows)
end

# Posts the new portfolio investment form through the real controller (Warden test login on an
# integration session; no browser), with the fields the form sends, for the instrument set up last.
# A rejected create re-renders the form, so the response is kept for the assertions rather than
# asserted < 400 as as_user_request does.
When('I submit the new portfolio investment form dated {string}') do |date|
  @portfolio_company ||= @entity.investors.portfolio_companies.last
  @pi_count = PortfolioInvestment.where(fund_id: @fund.id).count
  params = { portfolio_investment: { entity_id: @entity.id, fund_id: @fund.id, portfolio_company_id: @portfolio_company.id,
                                     investment_instrument_id: @investment_instrument.id,
                                     investment_date: expand_relative_dates(date), ex_expenses_base_amount: "10.00",
                                     quantity: "10.0", proforma: "0", notes: "" } }
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(@user, scope: :user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post(portfolio_investments_path, params:)
  @pi_response = session.response
ensure
  Warden.test_reset!
end

Then('the new portfolio investment form is shown again with {string}') do |text|
  expect(@pi_response.status).to eq(422), "Expected the form to re-render (422), got #{@pi_response.status}"
  expect(CGI.unescapeHTML(@pi_response.body.to_s)).to include(expand_relative_dates(text))
  expect(PortfolioInvestment.where(fund_id: @fund.id).count).to eq(@pi_count)
end

# For failures raised by a step other than the PI's own validation (e.g. the valuation it creates)
Then('the portfolio investment create fails with {string}') do |text|
  expect(@pi_result).not_to be_success
  expect(Array(@pi_result[:errors]).join(" ")).to include(expand_relative_dates(text))
  expect(@portfolio_investment).not_to be_persisted
end

### Investor Statement #########################################################

# Submits the commitment's Investor Statement form. The statement jobs are not run (capture them
# first), so the template id only has to be present.
def request_investor_statement(start_date, end_date, statement_for: nil)
  submit_as_logged_in_user(:patch, generate_soa_capital_commitment_path(@capital_commitment),
                           start_date: expand_relative_dates(start_date), end_date: expand_relative_dates(end_date),
                           template_id: "1", for: statement_for)
end

When('I request an Investor Statement from {string} to {string}') do |start_date, end_date|
  request_investor_statement(start_date, end_date)
end

When('I request an Investor Statement for Investing Entity from {string} to {string}') do |start_date, end_date|
  request_investor_statement(start_date, end_date, statement_for: "Investing Entity")
end
