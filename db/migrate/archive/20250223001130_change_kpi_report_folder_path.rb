class ChangeKpiReportFolderPath < ActiveRecord::Migration[7.2]
  def change
    KpiReport.includes(:document_folder).all.each do |kpi_report|
      kpi_report.document_folder.update!(full_path: kpi_report.folder_path)
    end
  end
end
