require 'open3'

class ConvertKpiToCsvJob < ApplicationJob
  queue_as :default

  def perform(kpi_report_id, user_id, kpi_file_id, action: 'csv')
    Chewy.strategy(:sidekiq) do
      case action
      when 'csv'
        convert_to_csv(kpi_report_id, user_id, kpi_file_id)
      when 'cleanup'
        cleanup_kpi_files(kpi_report_id, user_id, kpi_file_id)
      else
        Rails.logger.error "Unknown action for ConvertKpiToCsvJob: #{action}"
      end
    end
  end

  private

  def convert_to_csv(kpi_report_id, user_id, kpi_file_id)
    kpi_report = KpiReport.find(kpi_report_id)
    return unless kpi_report

    begin
      kpi_file = Document.find(kpi_file_id)

      kpi_file.file.download do |tmp_file|
        csv_file_path = "#{File.dirname(tmp_file.path)}/#{File.basename(tmp_file.path, '.*')}.csv"
        Rails.logger.debug { "Converting KPI file to CSV: #{kpi_file.name} -> #{csv_file_path}" }

        _, stderr, status = Open3.capture3("soffice --headless --convert-to csv --outdir #{File.dirname(csv_file_path)} #{tmp_file.path}")

        unless status.success?
          Rails.logger.error "LibreOffice conversion failed for #{kpi_file.name}. Stderr: #{stderr}"
          raise "LibreOffice conversion failed for #{kpi_file.name}. Details: #{stderr.strip}"
        end

        Rails.logger.debug { "Conversion completed: #{csv_file_path}" }
        doc = kpi_report.documents.create!(
          name: "#{kpi_file.name}.csv",
          file: File.open(csv_file_path),
          user_id: user_id,
          owner: kpi_report,
          entity_id: kpi_report.entity_id,
          orignal: true
        )

        Rails.logger.debug { "KPI CSV file created: #{doc.name} #{doc.id} for KpiReport #{kpi_report.id}" }
        FileUtils.rm_f(csv_file_path)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to convert KPI file to CSV: #{e.message}"
      send_notification("Failed to convert KPI file to CSV: #{e.message}", user_id, :error)
    end
  end

  def cleanup_kpi_files(kpi_report_id, user_id, kpi_file_id)
    kpi_file = Document.find(kpi_file_id)
    s3_url = kpi_file.file.url
    upload_url_data = kpi_file.file.storage.presign(kpi_file.file.id, method: :put)
    upload_url = upload_url_data[:url]
    upload_headers = upload_url_data[:headers]
    api_url = "#{ENV.fetch('XIRR_API', nil)}/cleanup_xlsx"

    conn = Faraday.new do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
    end

    response = conn.post(api_url) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = {
        s3_url: s3_url,
        upload_url: upload_url,
        upload_headers: upload_headers,
        replace: false
      }.to_json
    end

    Rails.logger.debug response.status
    Rails.logger.debug response.body

    if response.success?
      Rails.logger.debug { "Cleanup request successful for file #{kpi_file.name}, report #{kpi_report_id}" }
    else
      Rails.logger.error "Cleanup API failed for file #{kpi_file.name}, status: #{response.status}, body: #{response.body}"
      send_notification("Cleanup API failed for file #{kpi_file.name}", user_id, :error)
    end
  rescue StandardError => e
    Rails.logger.error "Failed during cleanup for KPI file: #{e.message}\n#{e.backtrace.join("\n")}"
    send_notification("Failed during cleanup for KPI file: #{e.message}", user_id, :error)
  end
end
