class AmlReportAsyncDownloadJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  def perform(aml_report_object_id, user_id)
    Chewy.strategy(:sidekiq) do
      aml_report = AmlReport.find(aml_report_object_id)
      json_res = AmlApiResponseService.new.get_report(aml_report)
      json_res = json_res.first
      handle_report_status(json_res, aml_report, user_id)
    rescue StandardError => e
      handle_error(e, aml_report, user_id)
    end
  end

  private

  def handle_report_status(json_res, aml_report, user_id)
    case json_res['status']
    when 'completed'
      process_completed_report(json_res, aml_report, user_id)
    when 'in_progress'
      AmlReportAsyncDownloadJob.set(wait: 60.seconds).perform_later(aml_report.id, user_id)
    else
      broadcast_failure(aml_report, user_id)
    end
  end

  def process_completed_report(json_res, aml_report, user_id)
    tmpfile = Tempfile.new(["AML Report - #{aml_report.investor_kyc.full_name}", '.pdf'])
    file_url = json_res.dig("result", "profile_pdf")
    if file_url.present?
      download_file(file_url, tmpfile)
      Document.create(entity: aml_report.entity, owner: aml_report, name: "AML Report - #{aml_report.investor_kyc.full_name}", file: File.open(tmpfile.path, "rb"), folder: aml_report.document_folder, user_id: user_id, orignal: true, owner_tag: "AML")
      UserAlert.new(user_id: user_id, message: "Downloaded Aml Report for #{aml_report.investor_kyc.full_name}", level: :success).broadcast if user_id.present?
      aml_report.match_status = json_res.dig("result", "match_status")&.titleize
      aml_report.save
    elsif user_id.present?
      broadcast_failure(aml_report, user_id)
    end
  end

  def download_file(file_url, tmpfile)
    require 'open-uri'
    URI.parse(file_url).open do |file|
      File.open(tmpfile.path, 'wb') do |output|
        while (chunk = file.read(1024)) # Read 1KB chunks
          output.write(chunk)
        end
      end
    end
  end

  def broadcast_failure(aml_report, user_id)
    UserAlert.new(user_id: user_id, message: "Failed to download Aml Report for #{aml_report.investor_kyc.full_name}", level: :danger).broadcast if user_id.present?
  end

  def handle_error(err, aml_report, user_id)
    Rails.logger.error "Failed to download Aml Report for #{aml_report.investor_kyc.full_name}: #{err.message}"
    UserAlert.new(user_id: user_id, message: "Failed to download Aml Report for #{aml_report.investor_kyc.full_name}: #{err.message}", level: :danger).broadcast if user_id.present?
    raise err
  end
end
