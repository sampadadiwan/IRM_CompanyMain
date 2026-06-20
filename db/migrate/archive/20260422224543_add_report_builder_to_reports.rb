class AddReportBuilderToReports < ActiveRecord::Migration[7.2]
  def change
    add_column :reports, :report_builder, :boolean, default: false, null: false
  end
end
