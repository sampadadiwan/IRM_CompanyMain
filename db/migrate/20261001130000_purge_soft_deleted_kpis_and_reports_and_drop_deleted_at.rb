# KPIs and KPI reports no longer soft-delete or audit (Trackable removed). Soft-deleted rows
# still hold investor_kpi_mapping_id, which blocks deleting the mapping via the FK, so purge them
# and then drop the now-unused deleted_at columns.
#
# Deploy the code first: old code that still includes Trackable queries deleted_at.
# Irreversible - purged rows cannot be restored, so take a backup first.
class PurgeSoftDeletedKpisAndReportsAndDropDeletedAt < ActiveRecord::Migration[8.1]
  BATCH_SIZE = 1000

  # Lightweight models: independent of app code and of any paranoia default scope.
  class MigrationKpi < ActiveRecord::Base
    self.table_name = "kpis"
  end

  class MigrationKpiReport < ActiveRecord::Base
    self.table_name = "kpi_reports"
  end

  def up
    purge_rows if column_exists?(:kpi_reports, :deleted_at)
    drop_deleted_at(:kpis)
    drop_deleted_at(:kpi_reports)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Children (kpis) before parents (kpi_reports): kpis.kpi_report_id has a foreign key.
  def purge_rows
    MigrationKpi.where.not(deleted_at: nil).in_batches(of: BATCH_SIZE).delete_all if column_exists?(:kpis, :deleted_at)
    deleted_report_ids = MigrationKpiReport.where.not(deleted_at: nil).select(:id)
    MigrationKpi.where(kpi_report_id: deleted_report_ids).in_batches(of: BATCH_SIZE).delete_all
    MigrationKpiReport.where.not(deleted_at: nil).in_batches(of: BATCH_SIZE).delete_all
  end

  def drop_deleted_at(table)
    remove_index table, :deleted_at if index_exists?(table, :deleted_at)
    remove_column table, :deleted_at if column_exists?(table, :deleted_at)
  end
end
