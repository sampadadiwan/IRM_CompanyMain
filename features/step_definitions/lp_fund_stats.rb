# Steps for features/fund/lp_fund_stats.feature - the LP fund page stats cards
# (CapitalRemittance.lp_totals / CapitalDistributionPayment.lp_totals, the lp_fund_stats_scope in
# both controllers, the _lp_stats partials and NumberStatsComponent#short_units).
# Amounts in the feature tables are major units of the fund currency; the models work in cents.

# An info-icon tooltip in the browser. Bootstrap 5.3 moves `title` to `data-bs-original-title` when it
# initialises the tooltip, so accept either (server-rendered HTML still has `title`).
TOOLTIP_ICON = ".ti-info-circle[data-bs-toggle='tooltip']:is([title], [data-bs-original-title])".freeze

module LpFundStatsHelpers
  # Major units in a feature table -> cents
  # Major units -> cents, keeping fractional paise (amount columns are decimal(20,2) cents)
  def stat_cents(major)
    BigDecimal(major.to_s) * 100
  end

  # A money amount as the page renders it (grid cell or stats card), back as a number to add up
  def shown_amount(money)
    BigDecimal(ApplicationController.helpers.money_to_currency(money, {}).gsub(/[^\d.-]/, ""))
  end

  # A stats card's cents as the card renders them
  def shown_card(cents)
    shown_amount(Money.new(cents, @fund.currency))
  end

  def lp_commitment
    @fund.capital_commitments.find_by!(investor_id: @investor.id)
  end

  # The scope the controllers build for the LP: every row the LP's investor scope reaches in this
  # fund, deduped by id (lp_fund_stats_scope)
  def lp_stats_scope(klass)
    klass.where(id: klass.for_investor(@investor_user).where(fund_id: @fund.id).select(:id))
  end

  # The text a stats card shows for an amount: same formatting as the partials, then the
  # component's unit shortening
  def stat_card_text(major)
    formatted = money_to_currency(Money.new(stat_cents(major), @fund.currency))
    NumberStatsComponent.new(path: nil, amount: formatted, subtitle: "", progress_bar_color: "primary").amount
  end

  # Checks each expected card (subtitle + amount) is present inside the given stats row
  def expect_stat_cards(container, rows)
    within(container) do
      rows.each do |row|
        subtitle = row["subtitle"]
        subtitle = "#{subtitle} (#{I18n.l(Date.parse(row['date']))})" if row["date"].present?
        # The card whose subtitle is exactly this one (so "Due" never picks the "Overdue" card)
        card = find(".card-subtitle", exact_text: subtitle).ancestor(".card")
        expect(card).to have_css("h2", exact_text: stat_card_text(row["amount"]))
      end
      # No extra cards beyond the ones listed
      expect(page).to have_css(".card-subtitle", count: rows.size)
    end
  end

  def truthy?(value)
    value.to_s.strip.casecmp("true").zero?
  end
end
World(LpFundStatsHelpers)

Given('the LP has these remittances in the fund:') do |table|
  commitment = lp_commitment
  table.hashes.each do |row|
    # Upload-basis call: no remittances are generated, so the one below is the only one on it
    capital_call = FactoryBot.create(:capital_call, fund: @fund, entity: @fund.entity, call_basis: "Upload", name: row["call"])
    remittance = FactoryBot.create(:capital_remittance, fund: @fund, entity: @fund.entity, capital_call:,
                                                        capital_commitment: commitment, investor: @investor,
                                                        folio_id: commitment.folio_id,
                                                        folio_committed_amount_cents: commitment.folio_committed_amount_cents)
    # Pin the exact figures; the save callbacks would otherwise derive them from the call
    remittance.update_columns(call_amount_cents: stat_cents(row["call_amount"]),
                              other_fee_cents: stat_cents(row["other_fee"]),
                              collected_amount_cents: stat_cents(row["collected"]),
                              verified: truthy?(row["verified"]), status: row["status"])
  end
  # update_columns skips counter_culture: rebuild the commitment/fund rollups (used by due_amount)
  CapitalRemittance.counter_culture_fix_counts
end

Given('the LP has these distribution payments in the fund:') do |table|
  commitment = lp_commitment
  table.hashes.each do |row|
    # generate_payments: false so the payment below is the only one on this distribution
    distribution = FactoryBot.create(:capital_distribution, fund: @fund, entity: @fund.entity, generate_payments: false,
                                                            title: row["title"], distribution_date: Date.parse(row["distribution_date"]))
    payment = FactoryBot.create(:capital_distribution_payment, fund: @fund, entity: @fund.entity,
                                                               capital_distribution: distribution, investor: @investor,
                                                               folio_id: commitment.folio_id)
    # Pin the exact figures (a blank payment date means a payment with no date recorded)
    payment.update_columns(gross_payable_cents: stat_cents(row["gross"]),
                           net_payable_cents: stat_cents(row["net"]),
                           tax_with_fees_cents: stat_cents(row["tax"]),
                           completed: truthy?(row["completed"]),
                           payment_date: row["payment_date"].present? ? Date.parse(row["payment_date"]) : nil)
  end
end

Given('the LP is granted access to the fund a second time') do
  # A category-wide fund right on top of the per-investor one from "the investors are added to the fund"
  AccessRight.create!(owner: @fund, access_type: "Fund", metadata: "Investor",
                      access_to_category: @investor.category, entity: @fund.entity)
end

Then("the LP's investor scope should repeat each remittance and distribution payment") do
  # Guard: without this the dedup scenario would prove nothing
  [CapitalRemittance, CapitalDistributionPayment].each do |klass|
    raw = klass.for_investor(@investor_user).where(fund_id: @fund.id)
    expect(raw.count).to be > raw.distinct.count(:id)
  end
end

Then('the LP remittance totals should be:') do |table|
  expected = table.rows_hash
  totals = CapitalRemittance.lp_totals(lp_stats_scope(CapitalRemittance))
  # Only the figures the table lists (fees is left out where no fees are charged)
  (expected.keys - ["overdue_count"]).each do |key|
    expect(totals[key.to_sym].to_i).to eq(stat_cents(expected[key])), "#{key}: got #{totals[key.to_sym]}"
  end
  expect(totals[:overdue_count]).to eq(expected["overdue_count"].to_i)
end

# Each card, as displayed, must equal the total of the grid cells as displayed
# (CapitalRemittance::INVESTOR_STANDARD_COLUMNS: Due Amount, Collected Amount, Under Verification, Status)
Then("the LP remittance totals should equal the totals of the LP grid columns") do
  scope = lp_stats_scope(CapitalRemittance)
  totals = CapitalRemittance.lp_totals(scope)
  rows = scope.to_a
  due_cells = rows.sum { |r| shown_amount(r.lp_due_amount) }
  collected_cells = rows.sum { |r| shown_amount(r.verified_collected_amount) }
  overdue_rows = rows.select { |r| r.status == "Overdue" }
  expect(shown_card(totals[:collected])).to eq(collected_cells)
  expect(shown_card(totals[:under_verification])).to eq(rows.sum { |r| shown_amount(r.under_verification_amount) })
  expect(shown_card(totals[:due])).to eq(due_cells)
  # Called = the Call Amount column, Fees = the Fees column
  expect(shown_card(totals[:called])).to eq(rows.sum { |r| shown_amount(r.call_amount) })
  expect(shown_card(totals[:fees])).to eq(rows.sum { |r| shown_amount(r.other_fee) })
  expect(shown_card(totals[:overdue])).to eq(overdue_rows.sum { |r| shown_amount(r.lp_due_amount) })
  expect(totals[:overdue_count]).to eq(overdue_rows.size)
end

# The Status cell of the LP grid (INVESTOR_STANDARD_COLUMNS "Status" => #lp_status) for one call
Then('the LP grid status of {string} should be {string}') do |call_name, expected|
  remittance = lp_stats_scope(CapitalRemittance).joins(:capital_call).find_by!(capital_calls: { name: call_name })
  expect(remittance.lp_status).to eq(expected)
end

# The badges the decorated Status cell renders in the LP grid ("Label:bg-class, ...")
Then('the LP grid status badges of {string} should be {string}') do |call_name, expected|
  remittance = lp_stats_scope(CapitalRemittance).joins(:capital_call).find_by!(capital_calls: { name: call_name })
  Draper::ViewContext.current = ApplicationController.new.view_context
  badges = Capybara.string(remittance.decorate.lp_status.to_s).all("span.badge").map do |badge|
    "#{badge.text.strip}:#{(badge[:class].split & %w[bg-success bg-info bg-warning bg-danger bg-secondary]).first}"
  end
  expect(badges).to eq(expected.split(",").map(&:strip))
end

# The commitment card's Due Amount (folio remittances, as _card.html.erb computes it) must equal the
# Calls section's Due for a one-folio LP, and the commitment's own verified-basis counters
Then("the commitment card's due amount should equal the LP remittance due") do
  commitment = lp_commitment.reload
  folio = CapitalRemittance.where(id: CapitalRemittance.for_investor(@investor_user).where(capital_commitment_id: commitment.id).select(:id))
  card_due = CapitalRemittance.lp_totals(folio)[:due]
  expect(card_due).to eq(CapitalRemittance.lp_totals(lp_stats_scope(CapitalRemittance))[:due])
  expect(card_due).to eq(commitment.due_amount.cents.truncate)
end

# (CapitalDistributionPayment::INVESTOR_STANDARD_COLUMNS: Net Payable, Payment Date, Completed)
Then("the LP distribution totals should equal the totals of the LP grid columns") do
  scope = lp_stats_scope(CapitalDistributionPayment)
  totals = CapitalDistributionPayment.lp_totals(scope)
  rows = scope.to_a
  received_cells = rows.select(&:completed).sum { |r| shown_amount(r.net_payable) }
  pending_cells = rows.reject(&:completed).sum { |r| shown_amount(r.net_payable) }
  last = rows.select { |r| r.completed && r.payment_date }.max_by { |r| [r.payment_date, r.id] }
  expect(shown_card(totals[:received])).to eq(received_cells)
  expect(shown_card(totals[:pending])).to eq(pending_cells)
  expect(shown_card(totals[:total])).to eq(received_cells + pending_cells)
  expect(totals[:last_date]).to eq(last&.payment_date)
  expect(shown_card(totals[:last_amount])).to eq(shown_amount(last.net_payable)) if last
end

Then('the LP distribution totals should be:') do |table|
  expected = table.rows_hash
  totals = CapitalDistributionPayment.lp_totals(lp_stats_scope(CapitalDistributionPayment))
  %w[total received pending last_amount].each do |key|
    expect(totals[key.to_sym].to_i).to eq(stat_cents(expected[key])), "#{key}: got #{totals[key.to_sym]}"
  end
  expect(totals[:last_date]).to eq(Date.parse(expected["last_date"]))
end

When('I open the Calls section of the fund page as the investor') do
  visit(fund_path(@fund))
  # Accordion section; the remittances frame is lazy and loads once expanded
  find("#calls-tab button.accordion-button").click
  expect(page).to have_css("#collapseCalls #lp_remittance_stats", wait: 15)
end

When('I open the Distributions section of the fund page as the investor') do
  visit(fund_path(@fund))
  find("#distributions-tab button.accordion-button").click
  expect(page).to have_css("#collapseDistributions #lp_distribution_stats", wait: 15)
end

Then('the LP remittance stats cards should be:') do |table|
  expect_stat_cards("#lp_remittance_stats", table.hashes)
end

Then('the LP distribution stats cards should be:') do |table|
  expect_stat_cards("#lp_distribution_stats", table.hashes)
end

Then('the LP distribution stats should not show the cards {string}') do |subtitles|
  within("#lp_distribution_stats") do
    subtitles.split(",").map(&:strip).each do |subtitle|
      expect(page).to have_no_css(".card-subtitle", text: subtitle)
    end
  end
end

When("I visit the fund's capital remittances list") do
  visit(capital_remittances_path(fund_id: @fund.id))
  # The list frame is rendered inline on this page, so once it is there the stats would be too
  expect(page).to have_css("turbo-frame#capital_remittances_frame", wait: 15)
end

Then('I should not see the LP remittance stats') do
  expect(page).to have_no_css("#lp_remittance_stats")
end

Then('the stats card amount {string} should render as {string}') do |amount, shown|
  html = ApplicationController.render(NumberStatsComponent.new(path: nil, amount:, subtitle: "Called", progress_bar_color: "primary"),
                                      layout: false)
  expect(Capybara.string(html).find("h2").text.strip).to eq(shown)
end

Then('the html-safe stats card amount {string} should render bold {string} followed by {string}') do |amount, bold, rest|
  html = ApplicationController.render(NumberStatsComponent.new(path: nil, amount: amount.html_safe, subtitle: "Called", # rubocop:disable Rails/OutputSafety
                                                               progress_bar_color: "primary"),
                                      layout: false)
  heading = Capybara.string(html).find("h2")
  # The <b> survived as markup (not escaped text), and the unit after it was shortened
  expect(heading).to have_css("b", exact_text: bold)
  expect(heading.text.strip).to eq("#{bold}#{rest}")
end

# S17/S18 - the LP fund page's help texts (section subtitles, stats card and grid header tooltips)
Then('the fund page sections should show their subtitles') do
  I18n.t("funds.fund_details.subtitles").each_value do |subtitle|
    expect(page).to have_css("#investorFundDetailsAccordion .accordion-header small.text-muted", text: subtitle, visible: :all)
  end
end

Then('every LP remittance stats card should have a help tooltip') do
  within("#lp_remittance_stats") do
    cards = all(".card")
    expect(cards).not_to be_empty
    cards.each { |card| expect(card).to have_css(TOOLTIP_ICON) }
  end
end

Then('the LP grid headers {string} should have help tooltips') do |labels|
  labels.split(",").map(&:strip).each do |label|
    header = find("#collapseCalls th", text: label, match: :first)
    expect(header).to have_css(TOOLTIP_ICON)
  end
end

Then('the remittance grid headers {string} should have help tooltips') do |labels|
  labels.split(",").map(&:strip).each do |label|
    expect(find("th", text: label, match: :first)).to have_css(TOOLTIP_ICON)
  end
end

# S19-S23 - help across the rest of the LP fund page (ratios, portfolio widgets, units, ?tab=)
module LpFundPageHelpHelpers
  # A view context (with a request, for the header's sort links) that answers current_user with
  # the given user, for decorators and components
  def view_context_as(user)
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    view = controller.view_context
    view.define_singleton_method(:current_user) { user }
    Draper::ViewContext.current = view
    view
  end

  def as_role(user, role)
    user.tap { |u| u.curr_role = role }
  end
end
World(LpFundPageHelpHelpers)

Then('the ratio help for {string} should mention {string}') do |name, text|
  expect(FundRatio.help_for(name)).to include(text)
end

Then('there should be no ratio help for {string}') do |name|
  expect(FundRatio.help_for(name)).to be_nil
end

Given('the fund has a ratio {string} with value {string}') do |name, value|
  @fund_ratio = FactoryBot.create(:fund_ratio, entity: @fund.entity, fund: @fund, owner: @fund, name:, display_value: value,
                                               end_date: Time.zone.today)
end

Then('the ratio grid should show help for {string} to an investor and to the fund team') do |name|
  ratio = FundRatio.find_by!(fund_id: @fund.id, name:)
  [as_role(@investor_user, "investor"), as_role(@user, "employee")].each do |user|
    view_context_as(user)
    expect(Capybara.string(ratio.decorate.name.to_s)).to have_css(".ti-info-circle[title*='paid-in']")
  end
end

Then('the ratio grid header should show column help to an investor and to the fund team') do
  [as_role(@investor_user, "investor"), as_role(@user, "employee")].each do |user|
    html = view_context_as(user).render(RansackTableHeader.new(FundRatio, q: nil, turbo_frame: nil, current_user: user, sortable: false,
                                                                          records: [@fund_ratio], entity: @fund.entity))
    expect(Capybara.string(html)).to have_css("th .ti-info-circle", count: FundRatio::COLUMN_HELP.size)
  end
end

Then('the {string} widget title should carry help') do |widget_name|
  component = WidgetCardComponent.new(widget: DashboardWidget.new(widget_name:), args: {})
  expect(component.instance_variable_get(:@help)).to eq(DashboardWidget::WIDGET_HELP.fetch(widget_name))
end

Then('a widget without help such as {string} should carry none') do |widget_name|
  component = WidgetCardComponent.new(widget: DashboardWidget.new(widget_name:), args: {})
  expect(component.instance_variable_get(:@help)).to be_nil
end

When('I open the {string} section of the fund page as the investor') do |section|
  visit(fund_path(@fund))
  find("##{section}-tab button.accordion-button").click
  expect(page).to have_css("#collapse#{section.capitalize} table", wait: 15)
end

Then('the {string} section grid headers should have help tooltips') do |section|
  # Unit Type, Issue Date, Quantity, Price, Premium, Amount, Reason
  expect(page).to have_css("#collapse#{section.capitalize} th #{TOOLTIP_ICON}", minimum: 7)
end

When('I visit the fund page with tab {string}') do |tab|
  visit(fund_path(@fund, tab:))
end

Then('the {string} section should be open') do |section|
  expect(page).to have_css("#collapse#{section}.show", wait: 10)
  # Still open once the tabs controller has run (it used to toggle an already-open section shut)
  sleep(1)
  expect(page).to have_css("#collapse#{section}.show")
end

# S24/S25 - the fund team's cards (recorded basis) on the commitment page tabs
Then("the fund team remittance totals for the LP's commitment should be:") do |table|
  expected = table.rows_hash
  totals = CapitalRemittance.grid_totals(lp_commitment.capital_remittances, verified_basis: false)
  # Only the figures the table lists (fees is left out where no fees are charged)
  (expected.keys - ["overdue_count"]).each do |key|
    expect(totals[key.to_sym].to_i).to eq(stat_cents(expected[key])), "#{key}: got #{totals[key.to_sym]}"
  end
  expect(totals[:overdue_count]).to eq(expected["overdue_count"].to_i)
end

# Each card, as displayed, equals the total of the fund team grid's cells as displayed
# (CapitalRemittance::FOR_COMMITMENT_COLUMNS: Due Amount, Collected Amount, Verified, Status)
Then('the fund team remittance totals should equal the totals of the fund team grid columns') do
  rows = lp_commitment.capital_remittances.to_a
  totals = CapitalRemittance.grid_totals(lp_commitment.capital_remittances, verified_basis: false)
  due_cells = rows.sum { |r| shown_amount(r.due_amount) }
  collected_cells = rows.sum { |r| shown_amount(r.collected_amount) }
  expect(shown_card(totals[:due])).to eq(due_cells)
  expect(shown_card(totals[:collected])).to eq(collected_cells)
  # Called = the Call Amount column, Fees = the Fees column
  expect(shown_card(totals[:called])).to eq(rows.sum { |r| shown_amount(r.call_amount) })
  expect(shown_card(totals[:fees])).to eq(rows.sum { |r| shown_amount(r.other_fee) })
  expect(shown_card(totals[:under_verification])).to eq(rows.reject(&:verified).sum { |r| shown_amount(r.collected_amount) })
  expect(shown_card(totals[:overdue])).to eq(rows.select { |r| r.status == "Overdue" }.sum { |r| shown_amount(r.due_amount) })
end

When("I open the {string} tab of the LP's commitment page") do |tab|
  visit(capital_commitment_path(lp_commitment)) unless page.current_path == capital_commitment_path(lp_commitment)
  find("a[href='##{tab}-tab']").click
  # The tab's list is a lazy turbo frame: it only loads once scrolled into the viewport, as when a
  # user scrolls down to it
  scroll_to(find("##{tab}-tab"))
  stats = tab == "remittances" ? "#lp_remittance_stats" : "#lp_distribution_stats"
  expect(page).to have_css("##{tab}-tab #{stats}", wait: 15)
end

Then('the stats cards in {string} should be:') do |container, table|
  expect_stat_cards(container, table.hashes)
end

# S26/S27 - fund unit stats cards (FundUnit.grid_totals)
Given("the LP's commitment has these fund units:") do |table|
  commitment = lp_commitment
  table.hashes.each do |row|
    unit = FactoryBot.create(:fund_unit, fund: @fund, entity: @fund.entity, capital_commitment: commitment, investor: @investor,
                                         unit_type: row["unit_type"], quantity: BigDecimal(row["quantity"]),
                                         price_cents: stat_cents(row["price"]), premium_cents: stat_cents(row["premium"]))
    # Amount is derived on save (quantity x (price + premium)); check the row is as the grid will show it
    expect(unit.reload.amount_cents).to eq(BigDecimal(row["quantity"]) * (stat_cents(row["price"]) + stat_cents(row["premium"])))
  end
end

Then("the fund unit totals for the LP's commitment should be:") do |table|
  expected = table.rows_hash
  totals = FundUnit.grid_totals(FundUnit.where(capital_commitment_id: lp_commitment.id))
  expect(totals[:units_by_type].transform_values(&:to_d)).to eq(expected.except("amount").transform_values { |v| BigDecimal(v) })
  expect(totals[:amount].to_d).to eq(stat_cents(expected["amount"]))
end

When("I open the Units tab of the LP's commitment page") do
  visit(capital_commitment_path(lp_commitment))
  find("a[href='#fund-units-tab']").click
  # Lazy turbo frame: loads once scrolled into the viewport
  scroll_to(find("#fund-units-tab"))
  expect(page).to have_css("#fund-units-tab #fund_unit_stats", wait: 15)
end

Then('the fund unit stats cards should be:') do |table|
  within("#fund_unit_stats") do
    table.hashes.each do |row|
      card = find(".card-subtitle", exact_text: row["subtitle"]).ancestor(".card")
      expect(card).to have_css("h2", exact_text: ActiveSupport::NumberHelper.number_to_delimited(BigDecimal(row["value"])))
    end
  end
end

Then('the fund unit Amount card should be {string}') do |amount|
  within("#fund_unit_stats") do
    card = find(".card-subtitle", exact_text: "Amount").ancestor(".card")
    expect(card).to have_css("h2", exact_text: stat_card_text(amount))
  end
end

# S28/S29 - headline ratio cards on the fund team's Ratios tab (FundRatio.headline_ratios)
Given('the fund has these ratios:') do |table|
  table.hashes.each do |row|
    FactoryBot.create(:fund_ratio, entity: @fund.entity, fund: @fund, owner: @fund, name: row["name"], display_value: row["display_value"],
                                   end_date: Date.parse(row["end_date"]), scenario: row["scenario"])
  end
end

Then('the headline ratio cards should be {string}') do |expected|
  cards = FundRatio.headline_ratios(FundRatio.where(fund_id: @fund.id)).map { |r| "#{r.name}=#{r.display_value}" }
  expect(cards).to eq(expected.split(",").map(&:strip))
end

When("I open the fund team's Ratios tab") do
  visit(fund_path(@fund))
  find("a[href='#fund-ratios-tab']").click
  expect(page).to have_css("#fund-ratios-tab #fund_ratio_headline_stats", wait: 15)
end

Then('I should see the headline ratio cards {string}') do |expected|
  within("#fund_ratio_headline_stats") do
    expected.split(",").map(&:strip).each do |pair|
      name, value = pair.split("=", 2)
      card = find(".card-subtitle", exact_text: name).ancestor(".card")
      expect(card).to have_css("h2", exact_text: value)
    end
    expect(page).to have_css(".card", count: expected.split(",").size)
  end
  # One shared date: a single line above the cards names the fund and the date
  expect(page).to have_css("#fund-ratios-tab #fund_ratios_subtitle", text: "Latest ratios for #{@fund.name}")
end
