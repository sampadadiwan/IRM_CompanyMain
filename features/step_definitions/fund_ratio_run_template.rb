# Step definitions for features/fund/fund_ratio_run_template.feature.
# Tests CRUD operations and trigger actions (single, all, by-tag) for
# FundRatioRunTemplate. Trigger steps run FundRatiosScenarioJob synchronously
# (perform_now) so the resulting FundRatioRun is available for assertions
# without async plumbing in the test environment.

### Helpers ####################################################################

# Parses a "key=value;key=value" string into a hash — same convention used
# across the fund_ratio_run step definitions.
def template_attrs_from_string(args)
  args.split(";").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    h[k.strip.to_sym] = v.to_s.strip
  end
end

# Finds a template by name within the current entity context (@entity).
def find_template!(name)
  FundRatioRunTemplate.find_by!(entity: @entity, name: name)
end

# Builds the fund_ids array for "both funds" steps — @fund and @fund_b must
# already be set by the "there is a second fund" background step.
def both_fund_ids
  [@fund.id, @fund_b.id]
end

# Dispatches the template synchronously and captures the resulting FundRatioRun.
def perform_template(template, end_date_str)
  end_date = Date.local_parse(end_date_str)
  # Replace perform_later with perform_now so the job completes before assertions.
  allow(FundRatiosScenarioJob).to receive(:perform_later) do |*args, **kwargs|
    FundRatiosScenarioJob.perform_now(*args, **kwargs)
  end
  template.enqueue(end_date: end_date, user_id: @user.id)
  end_date
end

### CRUD — create ##############################################################

When('I create a template {string} with the two funds') do |args|
  attrs = template_attrs_from_string(args)
  @template = FactoryBot.create(:fund_ratio_run_template,
                                entity:      @entity,
                                user:        @user,
                                anchor_fund: @fund,
                                name:        attrs[:name],
                                tags:        Array(attrs[:tag]),
                                fund_ids:    both_fund_ids)
end

When('I create a template {string}') do |args|
  attrs = template_attrs_from_string(args)
  @template = FundRatioRunTemplate.new(
    entity:                   @entity,
    user:                     @user,
    anchor_fund:              @fund,
    name:                     attrs[:name],
    tags:                     Array(attrs[:tag]),
    portfolio_companies_tags: attrs[:portfolio_companies_tags]
  )
  @template.save
end

# Used by the "names must be unique" scenario — expects save to fail.
When('creating another template {string} should fail with a validation error') do |args|
  attrs = template_attrs_from_string(args)
  duplicate = FundRatioRunTemplate.new(
    entity: @entity,
    user:   @user,
    name:   attrs[:name]
  )
  expect(duplicate.save).to be false
  expect(duplicate.errors[:name]).not_to be_empty
end

### CRUD — background Given ####################################################

Given('there is a template {string} for the entity') do |args|
  attrs = template_attrs_from_string(args)
  @template = FactoryBot.create(:fund_ratio_run_template,
                                entity: @entity,
                                user:   @user,
                                name:   attrs[:name],
                                tags:   Array(attrs[:tag]))
end

# "with both funds" variant — @fund_b must already exist.
Given('there is a template {string} with both funds for the entity') do |args|
  attrs = template_attrs_from_string(args)
  @template = FactoryBot.create(:fund_ratio_run_template,
                                entity:      @entity,
                                user:        @user,
                                anchor_fund: @fund,
                                name:        attrs[:name],
                                tags:        Array(attrs[:tag]),
                                fund_ids:    both_fund_ids)
end

# Single-fund variants — produce distinct fingerprints when two templates must
# map to two separate FundRatioRuns (Trigger All / Trigger by Tag scenarios).
Given('there is a template {string} with the first fund for the entity') do |args|
  attrs = template_attrs_from_string(args)
  @template = FactoryBot.create(:fund_ratio_run_template,
                                entity:      @entity,
                                user:        @user,
                                anchor_fund: @fund,
                                name:        attrs[:name],
                                tags:        Array(attrs[:tag]),
                                fund_ids:    [@fund.id])
end

Given('there is a template {string} with the second fund for the entity') do |args|
  attrs = template_attrs_from_string(args)
  @template = FactoryBot.create(:fund_ratio_run_template,
                                entity:      @entity,
                                user:        @user,
                                anchor_fund: @fund_b,
                                name:        attrs[:name],
                                tags:        Array(attrs[:tag]),
                                fund_ids:    [@fund_b.id])
end

### CRUD — update / destroy ####################################################

When('I update the template {string} name to {string}') do |old_name, new_name|
  find_template!(old_name).update!(name: new_name)
end

When('I destroy the template {string}') do |name|
  find_template!(name).destroy!
end

### Assertions — existence #####################################################

Then('a FundRatioRunTemplate should exist with name {string} and run_type {string}') do |name, run_type|
  tmpl = FundRatioRunTemplate.find_by(entity: @entity, name: name)
  expect(tmpl).not_to be_nil, "Expected FundRatioRunTemplate '#{name}' to exist"
  expect(tmpl.run_type).to eq(run_type)
end

Then('a FundRatioRunTemplate should exist with name {string} and tag {string}') do |name, tag|
  tmpl = FundRatioRunTemplate.find_by(entity: @entity, name: name)
  expect(tmpl).not_to be_nil, "Expected FundRatioRunTemplate '#{name}' to exist"
  # tags is now a JSON array; the scenario passes a single tag string.
  expect(tmpl.tags).to include(tag)
end

Then('no FundRatioRunTemplate should exist with name {string}') do |name|
  expect(FundRatioRunTemplate.find_by(entity: @entity, name: name)).to be_nil
end

Then('the template {string} should record both fund ids') do |name|
  tmpl = find_template!(name)
  expect(tmpl.fund_ids).to include(@fund.id, @fund_b.id)
end

Then('the template {string} should store portfolio_companies_tags {string}') do |name, tags|
  tmpl = find_template!(name)
  expect(tmpl.portfolio_companies_tags).to eq(tags)
end

### Trigger — single ###########################################################

When('I trigger template {string} for end_date {string}') do |name, date_str|
  @end_date = perform_template(find_template!(name), date_str)
end

Then('a FundRatioRun should exist with run_type {string} and end_date {string}') do |run_type, date_str|
  run = FundRatioRun.find_by(run_type:, end_date: Date.local_parse(date_str))
  expect(run).not_to be_nil, "Expected FundRatioRun run_type=#{run_type} on #{date_str}"
  @run = run
end

Then('FundRatios should exist linked to that FundRatioRun') do
  ratios = FundRatio.where(computation_context: @run)
  expect(ratios).not_to be_empty, "Expected FundRatios linked to FundRatioRun #{@run.id}"
end

### Trigger — all ##############################################################

When('I trigger all templates for end_date {string}') do |date_str|
  end_date = Date.local_parse(date_str)
  allow(FundRatiosScenarioJob).to receive(:perform_later) do |*args, **kwargs|
    FundRatiosScenarioJob.perform_now(*args, **kwargs)
  end
  FundRatioRunTemplate.for_entity(@entity.id).ordered.each do |tmpl|
    tmpl.enqueue(end_date: end_date, user_id: @user.id)
  end
  @end_date = end_date
end

Then('{int} FundRatioRuns should exist for end_date {string}') do |count, date_str|
  actual = FundRatioRun.where(entity: @entity, end_date: Date.local_parse(date_str)).count
  expect(actual).to eq(count), "Expected #{count} FundRatioRuns on #{date_str}, found #{actual}"
end

### Trigger — by tag ###########################################################

When('I trigger templates by tag {string} for end_date {string}') do |tag, date_str|
  end_date = Date.local_parse(date_str)
  allow(FundRatiosScenarioJob).to receive(:perform_later) do |*args, **kwargs|
    FundRatiosScenarioJob.perform_now(*args, **kwargs)
  end
  FundRatioRunTemplate.for_entity(@entity.id).for_tag(tag).ordered.each do |tmpl|
    tmpl.enqueue(end_date: end_date, user_id: @user.id)
  end
  @end_date = end_date
end

### Validation Rules ###########################################################

# Evaluates validation rules for a FundRatioRunTemplate with a given trigger_end_date.
# Mirrors the pattern used for other models in validation_rules.rb step definitions.
When('the validation rules are evaluated for a FundRatioRunTemplate {string} with trigger_end_date {string}') do |name, date_str|
  template = find_template!(name)
  template.trigger_end_date = Date.parse(date_str)

  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: template, entity: @entity)
  end
end

### Idempotency ################################################################

Then('only one FundRatioRun should exist for the template {string} on {string}') do |name, date_str|
  tmpl = find_template!(name)
  # The fingerprint of the template's stored inputs must match exactly one run.
  fingerprint = FundRatioRun.fingerprint(fund_ids: tmpl.fund_ids)
  count = FundRatioRun.where(entity: @entity, end_date: Date.local_parse(date_str), name: fingerprint).count
  expect(count).to eq(1), "Expected exactly 1 FundRatioRun for template '#{name}', found #{count}"
end
