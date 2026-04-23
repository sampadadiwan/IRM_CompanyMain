require 'tempfile'

class ReportBuilderExportJob < ApplicationJob
  queue_as :default

  def perform(report_id, user_id)
    report = Report.find(report_id)
    user   = User.find(user_id)
    entity = user.entity

    # 1. Generate data
    engine   = ReportBuilderQueryEngine.new(report: report, entity: entity)
    all_rows = engine.run
    exporter = ReportBuilderXlsxExporter.new(report: report, rows: all_rows, columns: engine.columns)
    
    filename = "#{report.name.parameterize.presence || 'report'}-#{Date.today.strftime('%d-%b-%Y')}.xlsx"
    
    # 2. Save to temporary file
    temp_file = Tempfile.new([report.name.parameterize, ".xlsx"])
    begin
      temp_file.binmode
      temp_file.write(exporter.generate)
      temp_file.rewind

      # 3. Create Document
      folder = Folder.find_by(entity_id: entity.id, name: "Reports") || Folder.find_by(entity_id: entity.id, level: 0)
      
      document = Document.new(
        name: report.name,
        entity: entity,
        user: user,
        folder: folder,
        owner: report,
        owner_tag: "Generated"
      )
      document.file = temp_file
      
      ActiveRecord::Base.connected_to(role: :writing) do
        document.save!
        report.update_column(:notify_last_run_at, Time.current)
        
        # Ensure access rights are set up immediately so the user can download it
        begin
          document.post_create_actions
        rescue StandardError => e
          Rails.logger.warn "[ReportBuilderExportJob] post_create_actions failed: #{e.message}"
        end
      end

      # 4. Notify User
      download_url = Rails.application.routes.url_helpers.show_file_document_path(document)
      message = "Your report <strong>#{report.name}</strong> is ready. <a href='#{download_url}' class='fw-bold text-decoration-underline'>Click here to download</a>."
      send_notification(message, user.id, "success")

    ensure
      temp_file.close
      temp_file.unlink
    end
  rescue StandardError => e
    Rails.logger.error "[ReportBuilderExportJob] Error: #{e.message}"
    send_notification("Failed to generate report <strong>#{report&.name || 'Unknown'}</strong>: #{e.message}", user_id, "danger")
  end
end
