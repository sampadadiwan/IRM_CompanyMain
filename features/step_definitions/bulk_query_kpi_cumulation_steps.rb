# Steps for features/startup/bulk_query_kpi_cumulation.feature (bulk-path-query-optimisation, phase 3).
# Setup and value checks reuse features/step_definitions/kpi.rb ("the following Monthly KPI Reports exist
# with KPIs:", "I run the KpiCumulateJob for the portfolio company", "I should see a {string} KPI ...");
# query counts use query_budget_steps.rb.

# E1: the job creates each missing Quarter/YTD report once and reuses it - never a second copy
Then('there should be {int} {string} KPI report(s) for {string}') do |count, period, as_of|
  reports = KpiReport.where(portfolio_company_id: @portfolio_company.id, entity_id: @entity.id, period: period, as_of: Date.parse(as_of))
  expect(reports.count).to eq(count)
end

# E11: a source KPI changed between two runs is read fresh by the second run (nothing outlives a job)
Given('the monthly {string} KPI for {string} is changed to {int}') do |kpi_name, as_of, value|
  Kpi.joins(:kpi_report)
     .find_by!(name: kpi_name, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: "Month", as_of: Date.parse(as_of) })
     .update!(value: value)
end

# X2 / E3: with the repeat skip a failure is reported once, not once per report that holds the KPI name
Then('the KPI cumulation error email should mention {string} once') do |text|
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present
  # The email renders each error row once per part (text + html), so count within one part
  part = mail.parts.any? ? mail.parts.first.body.decoded : mail.body.decoded
  expect(part.scan(text).size).to eq(1), "expected #{text.inspect} once in the error email, found #{part.scan(text).size}"
end

# X4: the RAG status of one period's cumulative KPI (rag_status holds the colour, as kpi.rb's step reads it)
Then('the {string} KPI {string} for {string} should have RAG status {string}') do |period, name, as_of, colour|
  kpi = Kpi.approved.joins(:kpi_report)
           .find_by!(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: Date.parse(as_of) })
  expect(kpi.rag_status).to eq(colour)
end
