# Steps for features/fund/evergreen/orders.feature (and reused by later evergreen features).
# Worked examples H7–H11, E3–E5, E13–E16, E18, X10–X16 — openspec/changes/open-ended-funds/design.md#worked-examples

After { travel_back }

Given('today is {string}') do |date|
  # Jumping weeks ahead would expire the Devise session (timeoutable); the scenarios are about dealing dates
  allow_any_instance_of(User).to receive(:timeout_in).and_return(100.years)
  # ...and keep the session cookie alive whatever date we travel to (features/support/evergreen_session_cookie.rb)
  EvergreenSessionCookie.travelling = true
  travel_to(Time.zone.parse("#{date} 10:00"))
end

# Log the browser out before signing in as someone else
def evergreen_fresh_login(user)
  Capybara.reset_sessions!
  @user = user
  steps %(
    And I am signed in as the current user
  )
end

Given('the evergreen fund {string} with classes {string} and settings {string}') do |name, classes, settings|
  steps %(Given there is a fund "name=#{name};currency=INR;unit_types=#{classes}" for the entity)
  @gp_user = @user
  make_fund_evergreen(@fund, @user, evergreen_kv(settings))
end

Given('class {string} of the fund has {string}') do |unit_type, settings|
  term = @fund.evergreen_class_terms.find_by!(unit_type:)
  kv = evergreen_kv(settings)
  kv[:early_redemption_fee] = EvergreenFormParsing.early_fee(kv.delete(:early_fee_pct), kv.delete(:early_fee_schedule), allow_nil: true) if kv.key?(:early_fee_pct) || kv.key?(:early_fee_schedule)
  term.update!(kv)
  # Orders read terms through the fund's cached setting
  @fund.reload.reset_evergreen_cache
end

Given('the fund setting has {string}') do |settings|
  kv = evergreen_kv(settings)
  kv[:early_redemption_fee] = EvergreenFormParsing.early_fee(kv.delete(:early_fee_pct), kv.delete(:early_fee_schedule)) if kv.key?(:early_fee_pct) || kv.key?(:early_fee_schedule)
  kv[:redemption_forms] = kv[:redemption_forms].split(",") if kv[:redemption_forms]
  kv[:redemption_dates] = kv[:redemption_dates].split(",") if kv[:redemption_dates]
  %i[min_initial_subscription min_additional_subscription min_holding].each { |k| kv[k] = kv[k].delete(",") if kv[k] }
  @fund.evergreen_fund_setting.update!(kv)
  @fund.reload.reset_evergreen_cache
end

# Every evergreen test investor has an approved KYC named after it: orders and folios need one
# (evergreen-folio-soa ①). Idempotent, so "has a verified KYC" and the setup steps can share it.
def evergreen_approved_kyc(inv)
  InvestorKyc.where(entity_id: inv.entity_id, investor_id: inv.id, verified: true).order(:id).first ||
    FactoryBot.create(:investor_kyc, entity: inv.entity, investor: inv, full_name: inv.investor_name, verified: true)
end

# An investor of the fund with a portal user and fund access
Given('{string} is an investor of the fund with a portal user') do |name|
  @gp_user ||= @user
  steps %(
    Given there is an existing investor "name=#{name}" with "1" users
  )
  AccessRight.create!(owner: @fund, access_type: "Fund", metadata: "Investor", access_to_investor_id: @investor.id, entity_id: @fund.entity_id)
  evergreen_approved_kyc(@investor)
  @investor_users ||= {}
  @investor_users[name] = @investor_user
end

When('{string} logs in to the portal') do |name|
  @investor_user = @investor_users.fetch(name)
  evergreen_fresh_login(@investor_user)
end

When('the fund admin logs in') do
  evergreen_fresh_login(@gp_user)
end

When('I start a {string} for the fund') do |kind|
  evergreen_visit(new_evergreen_order_path(@fund, kind:))
end

When('I fill the order with {string}') do |values|
  evergreen_kv(values).each do |field, value|
    case field
    when :investor then select(value, from: "order_investor")
    # Options read "F-012 · A · A Ltd": pick the one starting with the folio number (Capybara's :option needs exact text)
    when :folio then find("#order_folio").all("option").find { |o| o.text.start_with?(value) }.select_option
    when :class then select(value, from: "order_unit_type")
    when :received_at then find("#order_received_at").set(Time.zone.parse(value).strftime("%Y-%m-%dT%H:%M"))
    when :all_units then check("order_all_units")
    else fill_in("order_#{field}", with: value)
    end
  end
end

When('I check the order') do
  click_on("order_check")
end

# Side-effect buttons on the order pages ask first with the "Immediate Actions" popup; a rack_test run has
# no JS, so the button submits straight away and there is no popup to proceed in
def evergreen_order_proceed
  return if Capybara.current_driver == :rack_test

  within("#confirmModal") { click_on("Proceed") }
end

# Reject / Record payment open a small Bootstrap modal holding their fields (JS runs only)
def evergreen_open_order_modal(name)
  return if Capybara.current_driver == :rack_test

  find("##{name}_open").click
  expect(page).to have_css("##{name}_modal.show")
end

When('I submit the order') do
  check("order_acknowledge") if page.has_css?("#order_acknowledge", wait: 0)
  click_on("order_submit")
  evergreen_order_proceed
end

Then('the latest order should be:') do |table|
  order = DealingOrder.order(:id).last
  table.rows_hash.each do |field, expected|
    actual = case field
             when "dealing_date" then order.dealing_date.date.iso8601
             when "folio" then order.capital_commitment&.folio_id.to_s
             when "queue_position" then order.queue_position.to_s
             when "early_fee_pct", "units" then order.send(field).to_d.to_s
             else order.send(field).to_s
             end
    expected = expected.to_d.to_s if %w[early_fee_pct units].include?(field)
    expect(actual).to eq(expected), "#{field}: expected #{expected}, got #{actual}"
  end
end

Then('no order should have been created') do
  expect(DealingOrder.count).to eq(@orders_before.to_i)
end

Given('I note the order count') do
  @orders_before = DealingOrder.count
end

# Opening units for a folio of an investor (issued on a date) — reuses the NAV folio table step
Given('{string} holds {string} units of class {string} in folio {string} issued {string}') do |name, units, unit_type, folio, issued|
  inv = Investor.find_by(entity_id: @fund.entity_id, investor_name: name)
  unless inv
    steps %(Given there is an existing investor "name=#{name}")
    inv = @investor
  end
  cc = @fund.capital_commitments.find_by(folio_id: folio) ||
       CapitalCommitment.new(entity_id: @fund.entity_id, fund: @fund, investor: inv, unit_type:, folio_committed_amount_cents: 1_000_000,
                             orig_folio_committed_amount_cents: 1_000_000, folio_id: folio, folio_currency: @fund.currency,
                             fund_close: "Evergreen", commitment_date: Date.parse(issued),
                             investor_kyc_id: evergreen_approved_kyc(inv).id).tap { |c| c.save!(validate: false) }
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: inv, unit_type:,
                   quantity: units.delete(",").to_d, price_cents: 1_000_000, premium_cents: 0, issue_date: Date.parse(issued), reason: "Opening units")
end

Given('folio {string} is in {string}') do |folio, currency|
  @fund.capital_commitments.find_by!(folio_id: folio).update_columns(folio_currency: currency)
end

# Orders placed directly through the service (as an admin) at a received time
Given('{string} has placed a {string} order {string} received {string}') do |name, kind, values, received|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  kv = evergreen_kv(values)
  folio = @fund.capital_commitments.find_by(folio_id: kv.delete(:folio)) if kv[:folio]
  params = kv.merge(kind:, investor_id: inv.id, capital_commitment_id: folio&.id, unit_type: kv[:class] || "A", received_at: received)
  result = DealingOrderCreate.call(fund: @fund, params: params.except(:class), current_user: @gp_user || @user, source: "admin")
  raise "order failed: #{result[:errors]}" unless result.success?

  @last_order = result[:order]
end

When('I open the order book') do
  evergreen_visit(evergreen_orders_path(@fund))
end

Then('the order of {string} should show queue position {string}') do |name, pos|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(find("#order_#{order.id}")).to have_content("##{pos}")
end

When('I open the latest order') do
  evergreen_visit(evergreen_order_path(@fund, DealingOrder.order(:id).last))
end

When('I cancel the order') do
  click_on("cancel_order")
  evergreen_order_proceed
end

Then('{string} receives an email with subject {string} containing {string}') do |name, subject, body|
  user = @investor_users.fetch(name)
  open_email(user.email)
  expect(current_email.subject).to eq(subject)
  expect(current_email.body).to include(body)
end

When('I upload the order rows:') do |table|
  path = Rails.root.join("tmp/evergreen_order_upload_#{SecureRandom.hex(4)}.xlsx")
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Orders") do |sheet|
      sheet.add_row(ImportDealingOrder::STANDARD_HEADERS)
      table.raw.drop(1).each { |r| sheet.add_row(r) }
    end
    p.serialize(path.to_s)
  end
  @import_upload = ImportUpload.create!(name: "Orders upload", entity_id: @fund.entity_id, owner: @fund, user: @gp_user || @user,
                                        import_type: "DealingOrder", import_file: File.open(path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end

Then('the order upload should have {string} failed rows') do |count|
  expect(@import_upload.failed_row_count).to eq(count.to_i)
end

Then('the order upload results should mention {string}') do |text|
  file = @import_upload.reload.import_results.download
  rows = Roo::Spreadsheet.open(file.path, extension: :xlsx).sheet(0).to_a.flatten.compact.map(&:to_s)
  expect(rows.join(" | ")).to include(text)
end

# ---- Order book: one table with the gate's outcome per row, and the status filter (H34, E216–E218) ----

When('I open the redemptions list') do
  evergreen_visit(evergreen_orders_path(@fund, kind: "redemption"))
end

When('I open the order book filtered to {string}') do |label|
  key = { "Open" => "open", "Dealt" => "dealt", "Cancelled / rejected" => "closed", "All" => "all" }.fetch(label)
  evergreen_visit(evergreen_orders_path(@fund, filter: key))
end

Then('the order of {string} should show {string} at the gate') do |name, text|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(find("#order_#{order.id}")).to have_content(text)
end

Then('the order book should list the {string} order of {string}') do |kind, name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, kind:, investors: { investor_name: name }).order(:id).last
  expect(page).to have_css("#order_#{order.id}")
end

Then('the order book should not list the {string} order of {string}') do |kind, name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, kind:, investors: { investor_name: name }).order(:id).last
  expect(page).to have_no_css("#order_#{order.id}")
end

Then('the {string} cell of the order of {string} should show {string}') do |column, name, text|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  index = all("#orders thead th").map { |th| th.text.strip }.index(column)
  raise "No #{column} column" unless index

  expect(find("#order_#{order.id}").all("td")[index]).to have_content(text)
end
