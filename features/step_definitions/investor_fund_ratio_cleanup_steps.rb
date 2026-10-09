def create_fund_ratios(owner, count)
  count.times do
    FactoryBot.create(:fund_ratio, fund: @fund, entity: @fund.entity, owner: owner, name: "IRR", latest: true)
  end
end

Given('the investor has {int} fund ratios') do |count|
  create_fund_ratios(@investor, count)
end

Given('there is another investor {string} with {int} fund ratios') do |name, count|
  entity = FactoryBot.create(:entity, entity_type: "Investor", name: name)
  @other_investor = FactoryBot.create(:investor, investor_entity: entity, entity: @fund.entity)
  create_fund_ratios(@other_investor, count)
end

Given('the fund has {int} fund ratio owned by the fund') do |count|
  create_fund_ratios(@fund, count)
end

When('I open the investor page') do
  visit(investor_path(@investor))
end

When('I click delete on the investor page') do
  find("form.deleteButton button", match: :first).click
end

Then('the confirmation popup says {string}') do |text|
  within("#confirmModal") { expect(page).to have_content(text) }
end

When('I confirm the popup') do
  within("#confirmModal") { click_on("Proceed") }
end

When('I cancel the popup') do
  within("#confirmModal") { click_on("Cancel") }
end

When('the investor is deleted') do
  @investor.destroy
end

Then('the investor still exists') do
  expect(Investor.exists?(@investor.id)).to be true
end

Then("the investor now has {int} fund ratios") do |count|
  expect(FundRatio.where(owner: @investor).count).to eq(count)
end

Then("the investor's {int} fund ratios are soft deleted") do |count|
  expect(FundRatio.where(owner: @investor).count).to eq(0)
  expect(FundRatio.only_deleted.where(owner_type: "Investor", owner_id: @investor.id).count).to eq(count)
end

Then('the other investor still has {int} fund ratios') do |count|
  expect(FundRatio.where(owner: @other_investor).count).to eq(count)
end

Then('the fund still has {int} fund ratio owned by the fund') do |count|
  expect(FundRatio.where(owner: @fund).count).to eq(count)
end

# Soft-deletes the investor without running destroy callbacks, reproducing ratios orphaned
# before the cascade existed.
Given('the investor was deleted leaving its fund ratios orphaned') do
  @investor.update_column(:deleted_at, Time.current)
  expect(FundRatio.where(owner_type: "Investor", owner_id: @investor.id).count).to eq(4)
end

Given('the {string} widget is enabled on the {string}') do |widget_name, dashboard_name|
  # The company ratios widget lists only the owner ids it is given, so name the investor explicitly.
  metadata = "{ratio_names: ['IRR'], owner_type: ['Investor'], owner_id: [#{@investor.id}], latest: true}"
  DashboardWidget.create!(widget_name:, dashboard_name:, entity: @fund.entity, tags: "test", size: "XL",
                          name: "Default", enabled: true, metadata:)
end

When('I open the fund dashboard {string}') do |dashboard_name|
  visit(dashboard_fund_path(@fund, dashboard_name:))
end

When('I open the stakeholders portfolio dashboard') do
  visit(investors_path(multi_portfolio_dashboard: true, fund_ids: [@fund.id]))
end

# Same query as docs/operations/troubleshooting/orphaned_investor_fund_ratios.md
Then('the orphaned investor fund ratios query finds {int} ratios') do |count|
  orphans = FundRatio.where(owner_type: "Investor").where.not(owner_id: Investor.select(:id))
  expect(orphans.count).to eq(count)
  orphans.find_each(&:destroy)
  expect(FundRatio.where(owner: @investor).count).to eq(0)
  expect(FundRatio.where(owner: @other_investor).count).to eq(2)
end
