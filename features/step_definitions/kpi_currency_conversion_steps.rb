# frozen_string_literal: true

# Step definitions for KPI currency conversion cucumber tests.
# Covers: FX conversion on upload, recompute job, smart defaults, bulk import aliases.

# --- Setup Steps ---

Given('the portfolio company has kpi_currency {string}') do |currency|
  @portfolio_company.json_fields ||= {}
  @portfolio_company.json_fields['kpi_currency'] = currency
  @portfolio_company.save!
end

Given('the following exchange rates exist:') do |table|
  table.hashes.each do |row|
    ExchangeRate.find_or_create_by!(
      from: row['from'],
      to: row['to'],
      as_of: Date.parse(row['as_of']),
      entity: @entity
    ) do |er|
      er.rate = row['rate'].to_f
    end
  end
end

# Creates InvestorKpiMapping records for currency conversion tests.
# When fx_conversion_method is blank, the smart default callback sets it based on category.
Given('the following KPI mappings exist for currency conversion:') do |table|
  table.hashes.each do |row|
    attrs = {
      entity: @entity,
      investor: @portfolio_company,
      standard_kpi_name: row['name'],
      reported_kpi_name: row['name'],
      category: row['category'],
      data_type: 'money'
    }
    attrs[:fx_conversion_method] = row['fx_conversion_method'] if row['fx_conversion_method'].present?

    mapping = InvestorKpiMapping.find_or_initialize_by(
      entity: @entity,
      investor: @portfolio_company,
      standard_kpi_name: row['name']
    )
    mapping.assign_attributes(attrs)
    mapping.save!
  end
end

# Creates KPI reports and KPIs, applying FX conversion via KpiFxConverter
# the same way KpiWorkbookReader does during upload.
Given('the following Monthly KPI Reports exist with KPIs for currency conversion:') do |table|
  converter = KpiFxConverter.new(@portfolio_company)

  table.hashes.each do |row|
    as_of = Date.parse(row['as_of'])
    kpi_report = KpiReport.find_or_create_by!(
      entity: @entity,
      portfolio_company_id: @portfolio_company.id,
      period: 'Month',
      as_of: as_of,
      tag_list: 'Actual'
    ) do |r|
      r.user = @user
    end

    mapping = InvestorKpiMapping.find_by!(
      standard_kpi_name: row['name'],
      entity: @entity,
      investor: @portfolio_company
    )

    value = row['value'].to_f
    original_value = nil
    fx_rate = nil

    # Apply FX conversion the same way KpiWorkbookReader does
    rate = converter.resolve_fx_rate(mapping, kpi_report)
    if rate
      original_value = value
      fx_rate = rate
      value = value * rate
    end

    FactoryBot.create(:kpi,
      kpi_report: kpi_report,
      entity: @entity,
      portfolio_company_id: @portfolio_company.id,
      name: row['name'],
      value: value,
      display_value: value,
      original_value: original_value,
      fx_rate_used: fx_rate,
      investor_kpi_mapping: mapping,
      status: :approved
    )
  end
end

# --- Assertion Steps ---

Then('the KPI {string} for {string} should have value {string}') do |name, as_of, expected|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(
    name: name,
    entity_id: @entity.id,
    portfolio_company_id: @portfolio_company.id,
    kpi_reports: { as_of: date }
  ).last
  expect(kpi).not_to be_nil, "Expected KPI '#{name}' for #{as_of} to exist"
  expect(kpi.value.to_f).to eq(expected.to_f)
end

Then('the KPI {string} for {string} should have original_value {string}') do |name, as_of, expected|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(
    name: name,
    entity_id: @entity.id,
    portfolio_company_id: @portfolio_company.id,
    kpi_reports: { as_of: date }
  ).last
  expect(kpi).not_to be_nil
  expect(kpi.original_value.to_f).to eq(expected.to_f)
end

Then('the KPI {string} for {string} should have fx_rate_used {string}') do |name, as_of, expected|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(
    name: name,
    entity_id: @entity.id,
    portfolio_company_id: @portfolio_company.id,
    kpi_reports: { as_of: date }
  ).last
  expect(kpi).not_to be_nil
  expect(kpi.fx_rate_used.to_f).to eq(expected.to_f)
end

Then('the KPI {string} for {string} should have no original_value') do |name, as_of|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(
    name: name,
    entity_id: @entity.id,
    portfolio_company_id: @portfolio_company.id,
    kpi_reports: { as_of: date }
  ).last
  expect(kpi).not_to be_nil
  expect(kpi.original_value).to be_nil
end

# --- Recompute Steps ---

When('the exchange rate for {string} to {string} on {string} is updated to {string}') do |from, to, as_of, new_rate|
  date = Date.parse(as_of)
  er = ExchangeRate.find_by!(from: from, to: to, as_of: date, entity: @entity)
  er.update!(rate: new_rate.to_f)
end

When('I run the KPI currency recompute job') do
  KpiCurrencyRecomputeJob.perform_now(@portfolio_company.id, user_id: @user.id)
end

# --- Smart Default Steps ---

Then('the mapping {string} should have fx_conversion_method {string}') do |name, expected|
  mapping = InvestorKpiMapping.find_by!(
    standard_kpi_name: name,
    entity: @entity,
    investor: @portfolio_company
  )
  expect(mapping.fx_conversion_method).to eq(expected)
end

# --- Bulk Import Steps ---

# Simulates ImportInvestorKpiMapping by creating an ImportUpload and invoking the service.
When('I import KPI mappings with FX conversion values:') do |table|
  import_upload = ImportUpload.create!(
    entity: @entity,
    user: @user,
    import_type: 'InvestorKpiMapping',
    status: 'pending',
    file_name: 'test_fx_import.xlsx'
  )

  service = ImportInvestorKpiMapping.new

  table.hashes.each do |row|
    user_data = {
      "Stakeholder" => @portfolio_company.investor_name,
      "Reported Kpi Name" => row['reported_kpi_name'],
      "Standard Kpi Name" => row['standard_kpi_name'],
      "Category" => row['category'],
      "Data Type" => "money",
      "Denomination" => "",
      "Fx Conversion" => row['fx_conversion'],
      "Parent Standard Kpi Name" => "",
      "Position" => "",
      "Show In Report" => "yes",
      "Lower Threshold" => "",
      "Upper Threshold" => "",
      "Auto Fill" => "",
      "Compute Formula" => "",
      "Update Only" => ""
    }

    service.save_row(user_data, import_upload, [], {})
  end
end
