require 'open3'

class ConvertKpiToCsvJob < ApplicationJob
  queue_as :default

  def perform(id, user_id, kpi_file_id)
    Chewy.strategy(:sidekiq) do
      kpi_report = KpiReport.find(id)
      return unless kpi_report

      # Generate the CSV content by running libreoffice in headless mode
      begin
        kpi_file = Document.find(kpi_file_id)

        # Download the file
        kpi_file.file.download do |tmp_file|
          # Convert the file to CSV using LibreOffice in headless mode
          csv_file_path = "#{File.dirname(tmp_file.path)}/#{File.basename(tmp_file.path, '.*')}.csv"
          Rails.logger.debug { "Converting KPI file to CSV: #{kpi_file.name} -> #{csv_file_path}" }

          _, stderr, status = Open3.capture3("soffice --headless --convert-to csv --outdir #{File.dirname(csv_file_path)} #{tmp_file.path}")

          unless status.success?
              Rails.logger.error "LibreOffice conversion failed for #{kpi_file.name}. Stderr: #{stderr}"
              raise "LibreOffice conversion failed for #{kpi_file.name}. Details: #{stderr.strip}"
          end
          
          Rails.logger.debug { "Conversion completed: #{csv_file_path}" }
          # Upload the converted CSV file back to the document
          doc = kpi_report.documents.create!(
            name: "#{kpi_file.name}.csv",
            file: File.open(csv_file_path),
            user_id: user_id,
            owner: kpi_report,
            entity_id: kpi_report.entity_id,
            orignal: true
          )

          Rails.logger.debug { "KPI CSV file created: #{doc.name} #{doc.id} for KpiReport #{kpi_report.id}" }

          # Delete the temporary CSV file
          FileUtils.rm_f(csv_file_path)
        end
      rescue StandardError => e
        Rails.logger.error "Failed to convert KPI file to CSV: #{e.message}"
        send_notification("Failed to convert KPI file to CSV: #{e.message}", user_id, :error)
      end
    end
  end
end
