# frozen_string_literal: true
# Step definitions for KPI autofill on approval feature.
# Tests the approval → cumulation pipeline at the service/job level,
# not through the browser UI.

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────

Given('a portfolio company {string} exists under the current entity') do |name|
  # Create the portco's own entity first — the investor factory default
  # calls Entity.startups.sample.id which returns nil in an empty test DB.
  portco_entity = FactoryBot.create(:entity, name: name, entity_type: 'Startup')
  @portfolio_company = FactoryBot.create(:investor,
    investor_name: name,
    entity: @user.entity,
    investor_entity: portco_entity,
    category: 'Portfolio Company'
  )
end

Given('investor KPI mappings exist for {string} with autofill types:') do |name, table|
  pc = Investor.find_by!(investor_name: name)
  table.hashes.each do |row|
    # reported_kpi_name is required — before_create callback calls .strip on it
    FactoryBot.create(:investor_kpi_mapping,
      investor: pc,
      entity: pc.entity,
      reported_kpi_name: row['standard_kpi_name'],
      standard_kpi_name: row['standard_kpi_name'],
      autofill: row['autofill']
    )
  end
end

Given('{string} has pending quarterly KPIs:') do |name, table|
  pc = Investor.find_by!(investor_name: name)
  table.hashes.each do |row|
    report = KpiReport.find_or_create_by!(
      portfolio_company: pc,
      entity: pc.entity,
      as_of: Date.parse(row['as_of']),
      period: row['period'],
      user: @user
    )
    mapping = InvestorKpiMapping.find_by(
      investor: pc,
      standard_kpi_name: row['name']
    )
    FactoryBot.create(:kpi,
      kpi_report: report,
      name: row['name'],
      value: row['value'].to_f,
      entity: pc.entity,
      portfolio_company_id: pc.id,
      status: 'unapproved',
      investor_kpi_mapping: mapping
    )
  end
end

Given('{string} has an approved cumulated KPI with nil investor_kpi_mapping_id') do |name|
  pc = Investor.find_by!(investor_name: name)
  mapping = InvestorKpiMapping.find_by!(investor: pc, standard_kpi_name: 'Revenue')

  # Create 3 monthly source KPIs (Apr/May/Jun) with mapping assigned —
  # cumulation sums these into a Quarter record.
  %w[2025-04-30 2025-05-31 2025-06-30].each do |date|
    month_report = KpiReport.find_or_create_by!(
      portfolio_company: pc, entity: pc.entity,
      as_of: Date.parse(date), period: 'Month', user: @user
    )
    FactoryBot.create(:kpi,
      kpi_report: month_report, name: 'Revenue',
      value: 100_000_000, entity: pc.entity,
      portfolio_company_id: pc.id, status: 'approved',
      investor_kpi_mapping: mapping
    )
  end

  # Create the Quarter report with a legacy cumulated KPI that has nil mapping.
  quarter_report = KpiReport.find_or_create_by!(
    portfolio_company: pc, entity: pc.entity,
    as_of: Date.new(2025, 6, 30), period: 'Quarter', user: @user
  )
  @cumulated_kpi = Kpi.new(
    kpi_report: quarter_report, name: 'Revenue',
    value: 300_000_000, entity: pc.entity,
    portfolio_company_id: pc.id, status: 'approved',
    investor_kpi_mapping_id: nil
  )
  @cumulated_kpi.save!(validate: false)
end

Given('{string} has approved quarterly KPIs with forward_fill mapping:') do |name, table|
  pc = Investor.find_by!(investor_name: name)
  table.hashes.each do |row|
    report = KpiReport.find_or_create_by!(
      portfolio_company: pc,
      entity: pc.entity,
      as_of: Date.parse(row['as_of']),
      period: row['period'],
      user: @user
    )
    mapping = InvestorKpiMapping.find_by!(
      investor: pc,
      standard_kpi_name: row['name'],
      autofill: 'forward_fill'
    )
    FactoryBot.create(:kpi,
      kpi_report: report,
      name: row['name'],
      value: row['value'].to_f,
      entity: pc.entity,
      portfolio_company_id: pc.id,
      status: 'approved',
      investor_kpi_mapping: mapping
    )
  end
end

Given('{string} has no monthly KPI reports') do |name|
  pc = Investor.find_by!(investor_name: name)
  KpiReport.where(portfolio_company: pc, period: 'Month').destroy_all
end

# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS
# Use :test adapter so perform_later queues jobs instead of running inline —
# the inline adapter causes stack overflow (cumulation → percentage change →
# recursive triggers) and prevents inspecting enqueued_jobs.
# ─────────────────────────────────────────────────────────────────────────────

When('I approve all pending KPIs for {string}') do |name|
  pc = Investor.find_by!(investor_name: name)
  unapproved = Kpi.unapproved.joins(:kpi_report)
                   .where(kpi_reports: { portfolio_company_id: pc.id })
  @kpi_ids = unapproved.pluck(:id)
  ActiveJob::Base.queue_adapter = :test
  @approved_kpis = KpiApproveService.call(@kpi_ids, @user.id)
end

When('I approve the {string} KPI for {string} on {string}') do |kpi_name, as_of, company_name|
  pc = Investor.find_by!(investor_name: company_name)
  kpi = Kpi.joins(:kpi_report)
           .where(name: kpi_name, kpi_reports: { as_of: Date.parse(as_of), portfolio_company_id: pc.id })
           .first!
  ActiveJob::Base.queue_adapter = :test
  @approved_kpis = KpiApproveService.call([kpi.id], @user.id)
end

When('KpiCumulateJob runs for {string} with force') do |name|
  pc = Investor.find_by!(investor_name: name)
  KpiCumulateJob.perform_now(pc.id, user_id: @user.id, force: true)
end

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('a KpiCumulateJob should be enqueued with a scalar portfolio_company_id') do
  @enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
    (j['job_class'] || j[:job]&.to_s) == 'KpiCumulateJob'
  end
  expect(@enqueued_jobs.size).to eq(1)

  # Rails 8 test adapter uses string keys: "arguments" => [positional, {kwargs}]
  raw_args = @enqueued_jobs.first['arguments']
  @job_positional_arg = raw_args[0]
  @job_kwargs = raw_args[1] || {}

  expect(@job_positional_arg).to be_a(Integer)
end

Then('the enqueued job should have force true and compute_percentage_change true') do
  force = @job_kwargs['force'] || @job_kwargs[:force]
  cpc = @job_kwargs['compute_percentage_change'] || @job_kwargs[:compute_percentage_change]
  expect(force).to eq(true)
  expect(cpc).to eq(true)
end

Then('the enqueued job should have exactly {int} report ID(s)') do |count|
  report_ids = @job_kwargs['report_ids'] || @job_kwargs[:report_ids]
  expect(report_ids.size).to eq(count)
end

Then('after the job runs, YTD KPIs should exist for {string}') do |kpi_name|
  report_ids = @job_kwargs['report_ids'] || @job_kwargs[:report_ids]
  force = @job_kwargs['force'] || @job_kwargs[:force]
  cpc = @job_kwargs['compute_percentage_change'] || @job_kwargs[:compute_percentage_change]

  KpiCumulateJob.perform_now(
    @job_positional_arg,
    user_id: @user.id,
    force: force,
    report_ids: report_ids,
    compute_percentage_change: cpc
  )

  ytd_kpis = Kpi.joins(:kpi_report)
                .where(name: kpi_name)
                .where(kpi_reports: { portfolio_company_id: @portfolio_company.id, period: 'YTD' })
  expect(ytd_kpis.count).to be > 0
end

Then('the cumulated KPI should have an investor_kpi_mapping_id assigned') do
  @cumulated_kpi.reload
  expect(@cumulated_kpi.investor_kpi_mapping_id).not_to be_nil
end

Then('YTD KPIs should exist for {string} on {string}') do |kpi_name, company_name|
  pc = Investor.find_by!(investor_name: company_name)
  ytd_kpis = Kpi.joins(:kpi_report)
                .where(name: kpi_name)
                .where(kpi_reports: { portfolio_company_id: pc.id, period: 'YTD' })
  expect(ytd_kpis.count).to be > 0
end
