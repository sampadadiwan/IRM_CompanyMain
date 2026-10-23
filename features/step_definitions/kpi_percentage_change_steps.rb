# Steps for features/startup/kpi_ytd_yoy_percentage_change.feature

When('the KPI percentage change job runs') do
  KpiPercentageChangeJob.perform_now([@portfolio_company.id], @user.id)
end

# What the job does per group, but handed over as one list, so the comparison has to keep the groups apart itself
When('the percentage change is computed for all the approved KPIs in one list') do
  Kpi.recompute_percentage_change(Kpi.approved.joins(:kpi_report).preload(:kpi_report).to_a)
end

def kpi_for_change(period, name, as_of, tag: 'Actual', owner: nil)
  Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, owner_id: owner&.id,
                               kpi_reports: { period: period, as_of: Date.parse(as_of), tag_list: tag }).last
end

Given('the {string} KPI {string} for {string} has a stored percentage change of {float}') do |period, name, as_of, change|
  kpi_for_change(period, name, as_of).update_column(:percentage_change, change)
end

# The same KPI of two owners cannot share a report, because the name-per-report check refuses to save either. The
# comparison keeps owners apart anyway, so this lets the percentage change save them to show it.
Given('saving a KPI skips the check that its name is unique in the report') do
  allow_any_instance_of(Kpi).to(receive(:save).and_wrap_original { |original, *args, **kwargs| original.call(*args, **kwargs, validate: false) })
end

# A second owner's figures for the same KPI, tag and dates, written without the name-per-report check
Given('the following YTD KPIs of another owner exist:') do |table|
  @other_owner = FactoryBot.create(:entity)
  table.hashes.each do |row|
    report = KpiReport.find_by!(entity: @entity, portfolio_company_id: @portfolio_company.id, period: 'YTD', as_of: Date.parse(row['as_of']), tag_list: 'Actual')
    mapping = InvestorKpiMapping.find_by!(standard_kpi_name: row['name'], entity: @entity, investor: @portfolio_company)
    FactoryBot.build(:kpi, kpi_report: report, entity: @entity, portfolio_company_id: @portfolio_company.id, name: row['name'],
                           value: row['value'].to_f, investor_kpi_mapping: mapping, owner: @other_owner).save!(validate: false)
  end
end

Given('the {string} KPI mapping has a lower threshold of {int}') do |name, threshold|
  InvestorKpiMapping.find_by!(standard_kpi_name: name, entity: @entity, investor: @portfolio_company).update!(lower_threshold: threshold)
end

Then('the {string} KPI {string} for {string} should have a percentage change of {float}') do |period, name, as_of, change|
  expect(kpi_for_change(period, name, as_of).percentage_change.to_f).to eq(change)
end

Then('the {string} KPI {string} for {string} should have an empty percentage change') do |period, name, as_of|
  expect(kpi_for_change(period, name, as_of).percentage_change).to be_nil
end

Then('the {string} {string} KPI {string} for {string} should have a percentage change of {float}') do |tag, period, name, as_of, change|
  expect(kpi_for_change(period, name, as_of, tag: tag).percentage_change.to_f).to eq(change)
end

Then('the {string} KPI {string} for {string} owned by the other owner should have a percentage change of {float}') do |period, name, as_of, change|
  expect(kpi_for_change(period, name, as_of, owner: @other_owner).percentage_change.to_f).to eq(change)
end

# "empty" or a number, for scenario outlines that mix both outcomes
Then('the {string} KPI {string} for {string} should have the stored percentage change {string}') do |period, name, as_of, expected|
  stored = kpi_for_change(period, name, as_of).percentage_change
  expected == 'empty' ? expect(stored).to(be_nil) : expect(stored.to_f).to(eq(expected.to_f))
end

Then('the {string} KPI {string} for {string} should show "-" with no colour in the grid') do |period, name, as_of|
  kpi = kpi_for_change(period, name, as_of)
  within(".value_#{kpi.id}") do
    expect(page).to have_css('small.fs-1', exact_text: '-')
    expect(page).not_to have_css('.text-danger')
    expect(page).not_to have_css('.text-success')
  end
end

Then('the KPI page of the {string} KPI {string} for {string} should show "-" as its percentage change') do |period, name, as_of|
  visit(kpi_path(kpi_for_change(period, name, as_of)))
  expect(find('tr', text: 'Percentage Change').text).to eq('Percentage Change -')
end

Then('the KPI list should show "-" as the percentage change of the {string} KPI {string} for {string}') do |period, name, as_of|
  kpi = kpi_for_change(period, name, as_of)
  visit(kpis_path)
  expect(find("#kpi_#{kpi.id}")).to have_css('td', exact_text: '-')
end

When('I recompute the auto-fill for the portfolio company from the KPI grid') do
  visit(kpi_reports_path(portfolio_company_id: @portfolio_company.id, grid_view: true, entity_id: @user.entity_id, view_unapproved: true))
  click_on('Recompute Auto-Fill')
end
