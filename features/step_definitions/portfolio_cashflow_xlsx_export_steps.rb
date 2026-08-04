# Covers the regression where the "Download" link on an AggregatePortfolioInvestment's
# Income tab did not carry aggregate_portfolio_investment_id, so PortfolioCashflowsController#index
# fell back to policy_scope(PortfolioCashflow) and exported cashflows for every investment the
# user can see instead of just the one on the page.
#
# The download link's href is read straight from the rendered page (via Capybara) so the test
# exercises the real link, then fetched through a plain HTTP session so the raw xlsx bytes can be
# read back with Roo - same pattern as investor_kyc_xlsx_export_steps.rb.

require "tempfile"
require "uri"

Given('the last aggregate portfolio investment has cashflows {string}') do |amounts|
  api = AggregatePortfolioInvestment.last
  @apis ||= []
  @apis << api

  amounts.split("|").each do |amount|
    PortfolioCashflow.create!(
      entity: @entity,
      fund: api.fund,
      portfolio_company: api.portfolio_company,
      investment_instrument: api.investment_instrument,
      aggregate_portfolio_investment: api,
      payment_date: Date.today,
      amount: amount.to_d
    )
  end
end

When("I download the cashflows xlsx from the first aggregate portfolio investment's Income tab") do
  visit(aggregate_portfolio_investment_path(@apis.first))
  # find_link returns an absolute URL (Capybara runs against a live Puma server); the raw
  # session below defaults to a different host, so only the path+query carries over.
  download_path = URI.parse(find_link("Download", visible: :all)[:href]).request_uri

  @xlsx_session = ActionDispatch::Integration::Session.new(Rails.application)
  @xlsx_session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }

  @xlsx_session.get download_path
  expect(@xlsx_session.response.status).to eq(200)

  tempfile = Tempfile.new(["portfolio_cashflows_export", ".xlsx"], binmode: true)
  tempfile.write(@xlsx_session.response.body)
  tempfile.rewind

  @export_sheet = Roo::Spreadsheet.open(tempfile.path)
end

Then('the exported xlsx should contain only the cashflow amounts {string}') do |expected|
  expected_amounts = expected.split("|").map(&:to_d).sort

  headers = @export_sheet.row(1)
  amount_col = headers.index("Amount")
  raise "Column 'Amount' not found among exported headers: #{headers.inspect}" unless amount_col

  actual_amounts = (2..@export_sheet.last_row).map { |i| @export_sheet.row(i)[amount_col].to_d }.sort

  expect(actual_amounts).to eq(expected_amounts)
end
