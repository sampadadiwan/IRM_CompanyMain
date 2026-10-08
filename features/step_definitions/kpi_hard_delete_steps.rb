When('the KPI is deleted') do
  @kpi_id = @kpi.id
  @kpi.destroy!
end

When('the KPI report is deleted') do
  @kpi_ids = @kpi_report.kpis.pluck(:id)
  @kpi_report_id = @kpi_report.id
  @kpi_report.destroy!
end

When('the KPI value is changed to {string}') do |value|
  @kpi.update!(value: value.to_f)
end

When('the KPI mapping {string} is deleted') do |name|
  mapping = InvestorKpiMapping.find_by!(reported_kpi_name: name, investor: @portfolio_company)
  begin
    mapping.destroy!
  rescue ActiveRecord::InvalidForeignKey
    @mapping_delete_blocked = true
  end
end

Then('the KPI should no longer exist in the database') do
  expect(Kpi.unscoped.exists?(id: @kpi_id)).to be(false)
end

Then('the KPI report and its {string} KPIs should no longer exist in the database') do |count|
  expect(@kpi_ids.length).to eq(count.to_i)
  expect(KpiReport.unscoped.exists?(id: @kpi_report_id)).to be(false)
  expect(Kpi.unscoped.exists?(id: @kpi_ids)).to be(false)
end

Then('there should be no audit entries for KPIs or KPI reports') do
  expect(Audited::Audit.exists?(auditable_type: %w[Kpi KpiReport])).to be(false)
end

Then('the KPI mapping {string} should no longer exist') do |name|
  expect(@mapping_delete_blocked).to be_falsey
  expect(InvestorKpiMapping.unscoped.exists?(reported_kpi_name: name, investor: @portfolio_company)).to be(false)
end

Then('the KPI mapping {string} should still exist') do |name|
  expect(InvestorKpiMapping.unscoped.exists?(reported_kpi_name: name, investor: @portfolio_company)).to be(true)
end

# The test schema no longer has the legacy soft-delete column, so recreate it to stage pre-release data.
Given('the kpis and kpi_reports tables still have the legacy deleted_at column') do
  conn = ActiveRecord::Base.connection
  %w[kpis kpi_reports].each do |table|
    conn.add_column(table, :deleted_at, :datetime) unless conn.column_exists?(table, :deleted_at)
  end
  [Kpi, KpiReport].each(&:reset_column_information)
end

Given('that KPI and its report were soft-deleted before this release') do
  @legacy_kpi_id = @kpi.id
  @legacy_report_id = @kpi_report.id
  Kpi.where(id: @legacy_kpi_id).update_all(deleted_at: Time.current)
  KpiReport.where(id: @legacy_report_id).update_all(deleted_at: Time.current)
end

When('the purge migration runs') do
  require Rails.root.join("db/migrate/20261001130000_purge_soft_deleted_kpis_and_reports_and_drop_deleted_at.rb").to_s
  ActiveRecord::Migration.suppress_messages do
    PurgeSoftDeletedKpisAndReportsAndDropDeletedAt.new.migrate(:up)
  end
  [Kpi, KpiReport].each(&:reset_column_information)
end

Then('the legacy KPI and report should no longer exist in the database') do
  expect(Kpi.exists?(id: @legacy_kpi_id)).to be(false)
  expect(KpiReport.exists?(id: @legacy_report_id)).to be(false)
end

Then('the live KPI {string} should still exist') do |name|
  expect(Kpi.exists?(name:, portfolio_company_id: @portfolio_company.id)).to be(true)
  expect(KpiReport.exists?(portfolio_company_id: @portfolio_company.id)).to be(true)
end

Then('the kpis and kpi_reports tables should have no deleted_at column') do
  conn = ActiveRecord::Base.connection
  expect(conn.column_exists?(:kpis, :deleted_at)).to be(false)
  expect(conn.column_exists?(:kpi_reports, :deleted_at)).to be(false)
end

Then('a duplicate approved KPI {string} in the same report should be rejected') do |name|
  duplicate = Kpi.new(kpi_report: @kpi_report, entity: @entity, portfolio_company_id: @portfolio_company.id, name:, value: 1, status: :approved)
  expect(duplicate).not_to be_valid
  expect(duplicate.errors[:name]).to be_present
end
