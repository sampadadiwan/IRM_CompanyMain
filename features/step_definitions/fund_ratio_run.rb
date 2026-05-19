# Step definitions for features/fund/fund_ratio_run.feature.
# Tests the FundRatioRun audit model and cross-fund/cross-portfolio ratio generation.
# See docs/features/fund_ratio_run.md for full design rationale.

### Helpers ###################################################################

# Builds a minimal portfolio company + investment instrument + aggregate portfolio
# investment + one buy portfolio investment so FundRatioMultiFundCalcs has actual
# cash-flow data to work with. Returns the AggregatePortfolioInvestment.
def create_portfolio_company_with_investment(name:, sector:, tag_list:, fund:, entity:)
  # Every Investor needs a backing Entity of its own (the investor_entity).
  investor_entity = FactoryBot.create(:entity, entity_type: "Portfolio Company")
  pc = FactoryBot.build(:investor,
                         investor_name:      name,
                         category:           "Portfolio Company",
                         sector:             sector,   # used by Investor.in_sector scope
                         tag_list:           tag_list, # used by with_any_tags scope
                         entity:             entity,
                         investor_entity_id: investor_entity.id)
  pc.save!

  # One instrument per company is sufficient for the IRR calculation.
  instrument = FactoryBot.create(:investment_instrument,
                                  name:             "#{name} Stock",
                                  category:         "Unlisted",
                                  sub_category:     "Equity",
                                  entity:           entity,
                                  portfolio_company: pc)

  # AggregatePortfolioInvestment is the "position" record that holds the FMV.
  api = AggregatePortfolioInvestment.find_or_create_by!(
    entity:                entity,
    fund:                  fund,
    portfolio_company:     pc,
    investment_instrument: instrument
  )

  # A single buy transaction gives the XIRR calculation something to work with.
  pi = FactoryBot.build(:portfolio_investment,
                          entity:                        entity,
                          fund:                          fund,
                          portfolio_company:             pc,
                          investment_instrument:         instrument,
                          aggregate_portfolio_investment: api,
                          quantity:                      100,
                          investment_date:               Date.new(2022, 1, 1))
  pi.compute_amount_cents   # sets amount_cents, base_amount_cents
  pi.compute_all_numbers    # sets net_bought_amount_cents, net_amount_cents, cost_of_remaining_cents
  pi.save!

  # fmv_on_date raises unless a Valuation exists for the company + instrument
  # on or before the calculation date. Use a date safely before any test end_date.
  FactoryBot.create(:valuation,
                    entity:               entity,
                    owner:                pc,
                    investment_instrument: instrument,
                    valuation_date:       Date.new(2023, 12, 31),
                    per_share_value_cents: 150_000)

  api
end

### Step definitions ##########################################################

# Like the single-fund helper but lets each row specify which fund the company's
# investment belongs to. 'fund' column must be "first" or "second".
Given('there are portfolio companies in different funds for cross-portfolio testing:') do |table|
  @portfolio_companies_for_test = table.hashes.map do |row|
    # Map the human-readable fund column to the actual Fund record.
    fund = row['fund'] == 'second' ? @fund_b : @fund
    create_portfolio_company_with_investment(
      name:     row['name'],
      sector:   row['sector'] || 'Fintech',
      tag_list: row['tag_list'] || '',
      fund:     fund,
      entity:   @entity
    ).portfolio_company
  end
end

# Runs cross-portfolio with all company ids from @portfolio_companies_for_test AND
# restricts to @fund only via fund_ids filter. Stores @cp_fund_ids_filter for assertions.
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with all company ids and first fund filter') do |_scenario, date_str|
  @end_date           = Date.local_parse(date_str)
  pc_ids              = @portfolio_companies_for_test.map(&:id)
  @cp_fund_ids_filter = [@fund.id]
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_company_ids: pc_ids,
    fund_ids:              @cp_fund_ids_filter,
    type:                  "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(portfolio_company_ids: pc_ids, fund_ids: @cp_fund_ids_filter),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

# Runs cross-portfolio with all company ids but no fund_ids filter — both funds included.
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with all company ids and no fund filter') do |_scenario, date_str|
  @end_date = Date.local_parse(date_str)
  pc_ids    = @portfolio_companies_for_test.map(&:id)
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_company_ids: pc_ids,
    fund_ids:              nil,
    type:                  "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(portfolio_company_ids: pc_ids),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

# Runs cross-fund job passing nil as the anchor fund_id to verify the job handles it gracefully.
Given('the cross-fund ratios are computed with nil anchor fund on {string} with the two funds') do |date_str|
  @end_date = Date.local_parse(date_str)
  @fund_ids = [@fund.id, @fund_b.id]
  FundRatiosScenarioJob.perform_now(
    nil, @end_date, @user.id,
    fund_ids: @fund_ids,
    type:     "cross-fund"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(fund_ids: @fund_ids),
    end_date: @end_date,
    run_type: "cross-fund"
  )
end

Given('there is a second fund {string} for the entity') do |args|
  @fund_b = FactoryBot.build(:fund, entity: @entity)
  key_values(@fund_b, args)
  @fund_b.save!
end

# Creates portfolio companies from a data table and stores them in
# @portfolio_companies_for_test for use in subsequent compute/assertion steps.
Given('there are portfolio companies with sectors for cross-portfolio testing:') do |table|
  @portfolio_companies_for_test = table.hashes.map do |row|
    create_portfolio_company_with_investment(
      name:     row['name'],
      sector:   row['sector'],
      tag_list: row['tag_list'],
      fund:     @fund,
      entity:   @entity
    ).portfolio_company
  end
end

# Runs FundRatiosScenarioJob synchronously with both @fund and @fund_b as sources.
# Captures the resulting FundRatioRun in @run for assertion steps.
Given('the cross-fund ratios are computed for scenario {string} on {string} with the two funds') do |_scenario, date_str|
  @end_date  = Date.local_parse(date_str)
  @fund_ids  = [@fund.id, @fund_b.id]
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    fund_ids: @fund_ids,
    type:     "cross-fund"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(fund_ids: @fund_ids),
    end_date: @end_date,
    run_type: "cross-fund"
  )
end

# Runs with the explicit portfolio company IDs from @portfolio_companies_for_test.
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with portfolio company ids') do |_scenario, date_str|
  @end_date = Date.local_parse(date_str)
  pc_ids    = @portfolio_companies_for_test.map(&:id)
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_company_ids: pc_ids,
    type:                  "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(portfolio_company_ids: pc_ids),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

# Runs filtered by a single tag string passed through portfolio_companies_tags.
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with tag {string}') do |_scenario, date_str, tag|
  @end_date = Date.local_parse(date_str)
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_companies_tags: tag,
    type:                     "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(tags: tag),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

# Runs filtered by one or more sector strings (comma-separated in the feature).
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with sectors {string}') do |_scenario, date_str, sectors_str|
  @end_date = Date.local_parse(date_str)
  sectors   = sectors_str.split(",").map(&:strip)
  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_companies_sectors: sectors,
    type:                        "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(sectors: sectors),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

# Runs with a mixed filter table (portfolio_company / tag / sector rows).
# All three filter types are unioned inside FundRatioMultiFundCalcs.
Given('the cross-portfolio ratios are computed for scenario {string} on {string} with:') do |_scenario, date_str, table|
  @end_date = Date.local_parse(date_str)
  filters   = table.hashes.group_by { |r| r['filter'] }

  pc_names = (filters['portfolio_company'] || []).map { |r| r['value'] }
  pc_ids   = @entity.investors.where(investor_name: pc_names).pluck(:id)
  tags     = (filters['tag']    || []).map { |r| r['value'] }.join(",")
  sectors  = (filters['sector'] || []).map { |r| r['value'] }

  FundRatiosScenarioJob.perform_now(
    @fund.id, @end_date, @user.id,
    portfolio_company_ids:       pc_ids.presence,
    portfolio_companies_tags:    tags.presence,
    portfolio_companies_sectors: sectors.presence,
    type:                        "cross-portfolio"
  )
  @run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(portfolio_company_ids: pc_ids, tags: tags.presence, sectors: sectors.presence),
    end_date: @end_date,
    run_type: "cross-portfolio"
  )
end

### Assertions — FundRatioRun existence and contents ##########################

Then('a FundRatioRun should exist with run_type {string} and scenario {string}') do |run_type, _scenario|
  # scenario param kept in the step signature for readability but is no longer stored
  # on FundRatioRun — the run is identified by its fingerprint name instead.
  run = FundRatioRun.find_by(run_type:, end_date: @end_date)
  expect(run).not_to be_nil, "Expected a FundRatioRun with run_type=#{run_type} on #{@end_date}"
end

Then('the FundRatioRun should record both fund ids') do
  # fund_ids is a JSON array; verify both source funds are present.
  expect(@run.fund_ids).to include(@fund.id, @fund_b.id)
end

Then('the FundRatioRun should record both portfolio company ids') do
  expect(@run.portfolio_company_ids).to match_array(@portfolio_companies_for_test.map(&:id))
end

Then('the FundRatioRun should store sector {string}') do |sector|
  # sectors is a JSON array of strings stored on the run for audit purposes.
  expect(@run.sectors).to include(sector)
end

Then('the FundRatioRun for scenario {string} should store sector {string}') do |_scenario, sector|
  run = FundRatioRun.find_by(end_date: @end_date)
  expect(run).not_to be_nil
  expect(run.sectors).to include(sector)
end

### Assertions — idempotency ##################################################

Then('only one FundRatioRun should exist for the run\'s fingerprint on {string}') do |date_str|
  count = FundRatioRun.where(entity: @entity, end_date: Date.local_parse(date_str), name: @run.name).count
  expect(count).to eq(1), "Expected exactly 1 FundRatioRun with fingerprint '#{@run.name}', found #{count}"
end

Then('the FundRatios for the run should not be duplicated') do
  # delete_all + recreate on re-run must not leave two rows for the same metric.
  names = FundRatio.where(computation_context: @run).pluck(:name)
  dupes = names.tally.select { |_, c| c > 1 }
  expect(dupes).to be_empty, "Duplicate FundRatios detected after re-run: #{dupes}"
end

### Assertions — ratio names ##################################################

Then('the cross-fund run should contain ratios named:') do |table|
  expected_names = table.raw.flatten
  actual_names   = FundRatio.where(computation_context: @run).pluck(:name)
  expected_names.each do |name|
    expect(actual_names).to include(name),
      "Expected ratio '#{name}' but run produced only: #{actual_names.sort.inspect}"
  end
end

### Assertions — scenario column auto-population ##############################

Then('all FundRatios for the run should have scenario set to the run name') do
  # set_scenario_if_missing stores computation_context.name truncated to VARCHAR(40).
  # @run.name is a 64-char SHA-256 digest so we compare only the stored prefix.
  ratios = FundRatio.where(computation_context: @run)
  expect(ratios).not_to be_empty
  expected = @run.name.to_s.first(40)
  ratios.each do |fr|
    expect(fr.scenario).to eq(expected),
      "Expected scenario '#{expected}' on FundRatio '#{fr.name}' but got '#{fr.scenario.inspect}'"
  end
end

### Assertions — per-company metrics ##########################################

Then('per-company Value To Cost and MOIC FundRatios should exist for each selected portfolio company') do
  @portfolio_companies_for_test.each do |pc|
    ["Value To Cost", "MOIC"].each do |metric|
      ratio = FundRatio.find_by(owner: pc, name: metric, computation_context: @run)
      expect(ratio).not_to be_nil, "Expected #{metric} FundRatio for #{pc.investor_name}"
    end
  end
end

### Assertions — for_source_portfolio_company scope ###########################

Then('FundRatioRun.for_source_portfolio_company should return the run for each selected company') do
  @portfolio_companies_for_test.each do |pc|
    expect(FundRatioRun.for_source_portfolio_company(pc.id)).to include(@run),
      "Expected for_source_portfolio_company(#{pc.id}) to include run #{@run.id}"
  end
end

Then('FundRatioRun.for_source_portfolio_company should not return the run for an unrelated company') do
  # Build a company that was not in the run's portfolio_company_ids — the scope must exclude it.
  unrelated_entity = FactoryBot.create(:entity, entity_type: "Portfolio Company")
  unrelated = FactoryBot.create(:investor,
                                 investor_name:      "Unrelated Co",
                                 category:           "Portfolio Company",
                                 entity:             @entity,
                                 investor_entity_id: unrelated_entity.id)
  expect(FundRatioRun.for_source_portfolio_company(unrelated.id)).not_to include(@run)
end

### Assertions — FundRatio linkage ############################################

Then('all FundRatios for the run should have fund_id nil') do
  # Cross-run rows must not carry a fund_id — the computation context is on FundRatioRun.
  ratios = FundRatio.where(computation_context: @run)
  expect(ratios).not_to be_empty
  ratios.each do |fr|
    expect(fr.fund_id).to be_nil,
      "Expected fund_id nil on FundRatio '#{fr.name}' but got #{fr.fund_id}"
  end
end

Then('all FundRatios for the run should be linked to the FundRatioRun') do
  ratios = FundRatio.where(computation_context: @run)
  expect(ratios).not_to be_empty
  ratios.each do |fr|
    expect(fr.computation_context_id).to eq(@run.id)
    expect(fr.computation_context_type).to eq("FundRatioRun")
  end
end

Then('per-company FundRatios should exist for each selected portfolio company') do
  @portfolio_companies_for_test.each do |pc|
    irr = FundRatio.find_by(owner: pc, name: "IRR", computation_context: @run)
    expect(irr).not_to be_nil, "Expected IRR FundRatio for #{pc.investor_name}"
  end
end

Then('per-company FundRatios should exist for {string} and {string}') do |name_a, name_b|
  [name_a, name_b].each do |name|
    pc  = @entity.investors.find_by(investor_name: name)
    irr = FundRatio.find_by(owner: pc, name: "IRR", computation_context: @run)
    expect(irr).not_to be_nil, "Expected IRR FundRatio for #{name} (sector-filtered run)"
  end
end

Then('no FundRatios should exist for {string} in scenario {string}') do |name, _scenario|
  pc    = @entity.investors.find_by(investor_name: name)
  count = FundRatio.where(owner: pc, computation_context: @run).count
  expect(count).to eq(0),
    "Expected no FundRatios for #{name} in run #{@run&.name}, found #{count}"
end

Then('per-company FundRatios should exist for {string}, {string}, and {string} in scenario {string}') do |name_a, name_b, name_c, _scenario|
  # Confirms the union: each company was selected by a different filter type.
  [name_a, name_b, name_c].each do |name|
    pc  = @entity.investors.find_by(investor_name: name)
    irr = FundRatio.find_by(owner: pc, name: "IRR", computation_context: @run)
    expect(irr).not_to be_nil,
      "Expected IRR FundRatio for #{name} in union run '#{@run&.name}'"
  end
end

### Assertions — FundRatioRun scopes ##########################################

Then('FundRatioRun.for_source_fund should return the run for each selected fund') do
  # for_source_fund uses MEMBER OF against the multi-valued index on fund_ids.
  [@fund, @fund_b].each do |fund|
    expect(FundRatioRun.for_source_fund(fund.id)).to include(@run),
      "Expected for_source_fund(#{fund.id}) to include run #{@run.id}"
  end
end

Then('FundRatioRun.for_source_fund should not return the run for an unrelated fund') do
  # A fund not in the run's fund_ids array must not be returned by the scope.
  other_fund = FactoryBot.create(:fund, entity: @entity, name: "Unrelated Fund")
  expect(FundRatioRun.for_source_fund(other_fund.id)).not_to include(@run)
end

Then('FundRatioRun.for_source_sector {string} should return only the {string} run') do |sector, _scenario|
  expected_run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(sectors: [sector]),
    end_date: @end_date
  )
  results = FundRatioRun.for_source_sector(sector)
  expect(results).to include(expected_run)
  FundRatioRun.where.not(id: expected_run.id).each do |run|
    expect(results).not_to include(run) unless run.sectors.include?(sector)
  end
end

# Single-company variant: asserts an IRR FundRatio exists for the named company in @run.
Then('per-company FundRatios should exist for {string}') do |name|
  pc  = @entity.investors.find_by(investor_name: name)
  expect(pc).not_to be_nil, "Expected portfolio company '#{name}' to exist in the entity"
  irr = FundRatio.find_by(owner: pc, name: "IRR", computation_context: @run)
  expect(irr).not_to be_nil, "Expected IRR FundRatio for #{name} in run #{@run&.name}"
end

# Asserts for_source_fund returns @run for @fund (the first fund, used as fund_ids filter).
Then('FundRatioRun.for_source_fund should return the cross-portfolio run for the first fund') do
  expect(FundRatioRun.for_source_fund(@fund.id)).to include(@run),
    "Expected for_source_fund(#{@fund.id}) to include cross-portfolio run #{@run&.id}"
end

# Asserts for_source_fund does NOT return @run for @fund_b (excluded from the fund_ids filter).
Then('FundRatioRun.for_source_fund should not return the cross-portfolio run for the second fund') do
  expect(FundRatioRun.for_source_fund(@fund_b.id)).not_to include(@run),
    "Expected for_source_fund(#{@fund_b.id}) not to include cross-portfolio run #{@run&.id}"
end

# Asserts the FundRatioRun was created with anchor_fund nil (optional: true on the belongs_to).
Then('the FundRatioRun should have nil anchor_fund') do
  expect(@run).not_to be_nil, "Expected a FundRatioRun to exist"
  expect(@run.anchor_fund).to be_nil,
    "Expected anchor_fund to be nil but got #{@run.anchor_fund&.name}"
end

# for_source_tag uses CONCAT(',', col, ',') LIKE "%,tag,%" rather than MEMBER OF
# because portfolio_companies_tags is a plain comma-separated string, not a JSON array.
Then('FundRatioRun.for_source_tag {string} should return only the {string} run') do |tag, _scenario|
  expected_run = FundRatioRun.find_by(
    name:     FundRatioRun.fingerprint(tags: tag),
    end_date: @end_date
  )
  results = FundRatioRun.for_source_tag(tag)
  expect(results).to include(expected_run)
  FundRatioRun.where.not(id: expected_run.id).each do |run|
    stored_tags = run.portfolio_companies_tags.to_s.split(",").map(&:strip)
    expect(results).not_to include(run) unless stored_tags.include?(tag)
  end
end
