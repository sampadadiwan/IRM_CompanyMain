class AddSubmissionStatusToKpiReports < ActiveRecord::Migration[7.1]
  def change
    add_column :kpi_reports, :status, :string, default: 'shell_created', null: false
    add_column :kpi_reports, :submitted_at, :datetime
    add_column :kpi_reports, :link_sent_at, :datetime
    add_index :kpi_reports, :status
  end
end
