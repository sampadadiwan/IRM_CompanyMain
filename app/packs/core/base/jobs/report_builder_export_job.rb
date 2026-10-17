require 'tempfile'

class ReportBuilderExportJob < ApplicationJob
  queue_as :default

  def perform(report_id, user_id, schedule_id = nil)
    # Declared outside the block so the rescue below can name the report; it used to be local to the
    # block, so any failure raised NameError and the "Failed to generate report" alert never showed.
    report = nil
    Chewy.strategy(:sidekiq) do
      report = Report.find(report_id)
      user   = User.find(user_id)
      schedule = ReportSchedule.find_by(id: schedule_id) if schedule_id
      # R4: a SCHEDULED run belongs to the report's entity. users.entity_id is wherever the owner is
      # switched right now (advisors), so a schedule used to query - and email to the schedule's
      # recipients - another tenant's data. On-demand exports keep using the requesting user's
      # entity, as before (R4-H). A report with no entity falls back to the user's, as before.
      # Worked examples R4, R4-H — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
      entity = schedule && report.entity ? report.entity : user.entity

      # A scheduled run reads the report's entity with the owner's name on it, so the owner must still
      # belong there: their company (home included), a group parent of it, or an advisor grant on it.
      # A removed advisor's schedule would otherwise keep emailing that company's data (R4-X).
      if schedule && report.entity && !owner_still_belongs?(user, report.entity)
        Rails.logger.warn("[ReportBuilderExportJob] Skipping schedule #{schedule.id}: user #{user.id} no longer belongs to entity #{report.entity_id}")
        return
      end

      # 1. Generate data
      engine   = ReportBuilderQueryEngine.new(report: report, entity: entity)
      # computed_sort_cap: nil — a download must contain every matching row
      # regardless of sort column, not just the first N used for on-screen sorting.
      all_rows = engine.run(computed_sort_cap: nil)
      exporter = ReportBuilderXlsxExporter.new(report: report, rows: all_rows, columns: engine.columns)

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
          owner_tag: "Generated",
          orignal: true
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

        # 4. Send Email if scheduled
        ReportMailer.scheduled_report(report, schedule.recipients, temp_file.path).deliver_now if schedule

        # 5. Notify User (if not scheduled or also notify owner)
        download_url = Rails.application.routes.url_helpers.document_path(document)
        message = "Your report <strong>#{report.name}</strong> is ready. <a href='#{download_url}' target='_blank' class='btn btn-success btn-sm'>Click here to download</a>."
        UserAlert.new(user_id: user.id, entity_id: entity.id, message:, level: "success").broadcast
      ensure
        temp_file.close
        temp_file.unlink
      end
    end
  rescue StandardError => e
    Rails.logger.error "[ReportBuilderExportJob] Error: #{e.message}"
    error_user = User.find_by(id: user_id)
    UserAlert.new(user_id: error_user.id, entity_id: error_user.entity_id, message: "Failed to generate report <strong>#{report&.name || 'Unknown'}</strong>: #{e.message}", level: "danger").broadcast if error_user
  end

  private

  # Worked examples R4, R4-X — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def owner_still_belongs?(user, entity)
    [user.entity_id, user.advisor_entity_id].compact.include?(entity.id) ||
      (user.entity_type == "Group Company" && user.entity&.child_ids&.include?(entity.id)) ||
      InvestorAdvisor.exists?(user_id: user.id, entity_id: entity.id)
  end
end
