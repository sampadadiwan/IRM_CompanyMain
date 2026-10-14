# Steps for features/fund/lp_fund_stats.feature - the LP fund page stats cards
# (CapitalRemittance.lp_totals / CapitalDistributionPayment.lp_totals, the lp_fund_stats_scope in
# both controllers, the _lp_stats partials and NumberStatsComponent#short_units).
# Amounts in the feature tables are major units of the fund currency; the models work in cents.

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
  %w[called collected due overdue].each do |key|
    expect(totals[key.to_sym].to_i).to eq(stat_cents(expected[key])), "#{key}: got #{totals[key.to_sym]}"
  end
  expect(totals[:overdue_count]).to eq(expected["overdue_count"].to_i)
end

# Each card, as displayed, must equal the total of the grid cells as displayed
# (CapitalRemittance::INVESTOR_STANDARD_COLUMNS: Due Amount, Collected Amount, Status)
Then("the LP remittance totals should equal the totals of the LP grid columns") do
  scope = lp_stats_scope(CapitalRemittance)
  totals = CapitalRemittance.lp_totals(scope)
  rows = scope.to_a
  due_cells = rows.sum { |r| shown_amount(r.due_amount) }
  collected_cells = rows.sum { |r| shown_amount(r.collected_amount) }
  overdue_rows = rows.select { |r| r.status == "Overdue" }
  expect(shown_card(totals[:collected])).to eq(collected_cells)
  expect(shown_card(totals[:due])).to eq(due_cells)
  expect(shown_card(totals[:called])).to eq(due_cells + collected_cells)
  expect(shown_card(totals[:overdue])).to eq(overdue_rows.sum { |r| shown_amount(r.due_amount) })
  expect(totals[:overdue_count]).to eq(overdue_rows.size)
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
