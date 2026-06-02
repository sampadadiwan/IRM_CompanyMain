# Step definitions for features/fund/fund_ratio_run_resolved_portfolio_companies.feature.
# Tests FundRatioRun#resolved_portfolio_companies directly against a persisted run record,
# covering all filter combinations: explicit IDs, tags, sectors, and their interactions.

### Helpers ###################################################################

# Creates and saves a FundRatioRun with the given filter inputs against @entity / @user.
def build_frr(portfolio_company_ids: [], portfolio_companies_tags: nil, sectors: [])
  FundRatioRun.create!(
    entity:                   @entity,
    end_date:                 Date.new(2024, 3, 31),
    run_type:                 "cross-portfolio",
    user:                     @user,
    portfolio_company_ids:    portfolio_company_ids,
    portfolio_companies_tags: portfolio_companies_tags,
    sectors:                  sectors
  )
end

# Resolves a comma-separated list of company names to their DB ids within @entity.
def frr_pc_ids_for(name_csv)
  name_csv.split(",").map(&:strip).map do |name|
    @entity.investors.find_by!(investor_name: name).id
  end
end

### Background ################################################################

Given('the entity has portfolio companies for resolved_portfolio_companies testing:') do |table|
  table.hashes.each do |row|
    investor_entity = FactoryBot.create(:entity, entity_type: "Portfolio Company")
    FactoryBot.create(:investor,
                       investor_name:      row['name'],
                       category:           "Portfolio Company",
                       sector:             row['sector'],
                       tag_list:           row['tag_list'],
                       entity:             @entity,
                       investor_entity_id: investor_entity.id)
  end
end

### Run creation ##############################################################

Given('a FundRatioRun exists with no portfolio company filters') do
  @run = build_frr
end

Given('a FundRatioRun exists with explicit companies {string}') do |names|
  @run = build_frr(portfolio_company_ids: frr_pc_ids_for(names))
end

Given('a FundRatioRun exists with tags {string}') do |tags|
  @run = build_frr(portfolio_companies_tags: tags)
end

Given('a FundRatioRun exists with sectors {string}') do |sectors|
  @run = build_frr(sectors: sectors.split(",").map(&:strip))
end

Given('a FundRatioRun exists with tags {string} and sectors {string}') do |tags, sectors|
  @run = build_frr(
    portfolio_companies_tags: tags,
    sectors:                  sectors.split(",").map(&:strip)
  )
end

Given('a FundRatioRun exists with explicit companies {string}, tags {string}, and sectors {string}') do |names, tags, sectors|
  @run = build_frr(
    portfolio_company_ids:    frr_pc_ids_for(names),
    portfolio_companies_tags: tags,
    sectors:                  sectors.split(",").map(&:strip)
  )
end

### Assertions ################################################################

Then('resolved_portfolio_companies should be nil') do
  expect(@run.resolved_portfolio_companies).to be_nil
end

Then('resolved_portfolio_companies should return no companies') do
  result = @run.resolved_portfolio_companies
  expect(result).not_to be_nil, "Expected an empty relation, not nil"
  expect(result.to_a).to be_empty,
    "Expected no companies but got: #{result.pluck(:investor_name).inspect}"
end

Then('resolved_portfolio_companies should return exactly {string}') do |names|
  expected = names.split(",").map(&:strip).sort
  result   = @run.resolved_portfolio_companies
  expect(result).not_to be_nil, "Expected a relation, not nil"
  actual = result.pluck(:investor_name).sort
  expect(actual).to match_array(expected),
    "Expected #{expected.inspect} but got #{actual.inspect}"
end
