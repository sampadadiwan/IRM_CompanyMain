require 'tempfile'

class ReportBuilderExportJob < ApplicationJob
  queue_as :default

  # test_send: "Send test to me" — the same file and email, to the user alone
  # (report-builder-delivery H6, H8). A keyword with a default, so jobs queued
  # before a deploy still run.
  def perform(report_id, user_id, schedule_id = nil, test_send: false)
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

      # 1. Generate data. M16 — the rows are limited to a user's Pundit scope: a scheduled run uses the
      # report's owner (report.user, whose firm membership H17 / R4-X check), an on-demand export the
      # user who asked for it, so a download never holds more than that user sees on screen (M16-4)
      scope_user = schedule ? report.user : user
      engine   = ReportBuilderQueryEngine.new(report: report, entity: entity, user: scope_user)
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

        # 4. Send Email if scheduled, or to the user alone for a test
        if schedule
          ReportMailer.scheduled_report(report, schedule.recipients, temp_file.path).deliver_now
          # "Last sent" is when the email actually went out; the scheduler set it when it queued the run (H7)
          schedule.update_columns(last_run_at: Time.current)
        elsif test_send
          ReportMailer.scheduled_report(report, [user.email], temp_file.path).deliver_now
        end

        # 5. Notify User (if not scheduled or also notify owner)
        download_url = Rails.application.routes.url_helpers.document_path(document)
        name = ERB::Util.h(report.name)
        message = if test_send
                    "A test of <strong>#{name}</strong> was emailed to #{ERB::Util.h(user.email)}."
                  else
                    "Your report <strong>#{name}</strong> is ready. <a href='#{download_url}' target='_blank' class='btn btn-success btn-sm'>Click here to download</a>."
                  end
        UserAlert.new(user_id: user.id, entity_id: entity.id, message:, level: "success").broadcast

        # 6. On the page the user is looking at: Export becomes Download and the file joins
        # Recent exports (H1, H2). Not for scheduled runs — the owner isn't waiting on a button.
        broadcast_export_done(report, user, document) unless schedule
      ensure
        temp_file.close
        temp_file.unlink
      end
    end
  rescue StandardError => e
    Rails.logger.error "[ReportBuilderExportJob] Error: #{e.message}"
    error_user = User.find_by(id: user_id)
    if error_user
      message = "Couldn't export <strong>#{ERB::Util.h(report&.name || 'the report')}</strong>: #{ERB::Util.h(e.message)}"
      UserAlert.new(user_id: error_user.id, entity_id: error_user.entity_id, message:, level: "danger").broadcast
      # The button goes back to Export XLSX so the user can try again (X1)
      broadcast_button(report, error_user, state: :idle) if report && schedule_id.nil?
    end
  end

  private

  # Export → Download, and the new file at the top of Recent exports, over the
  # alert stream every page already listens on (user_alert_<id>)
  def broadcast_export_done(report, user, document)
    broadcast_button(report, user, state: :ready, document: document)
    Turbo::StreamsChannel.broadcast_replace_to("user_alert_#{user.id}", target: "rb_recent_exports_#{report.id}",
                                                                        partial: "report_builder/recent_exports",
                                                                        locals: { report: report, user: user })
  end

  # The report page's button and the builder header's small one have their own ids
  # (rb_export_<id> / rb_export_<id>_sm); the job can't know which page is open, so it
  # replaces both — only one is ever on a page, the other replace finds nothing
  def broadcast_button(report, user, state:, document: nil)
    [nil, :sm].each do |size|
      Turbo::StreamsChannel.broadcast_replace_to("user_alert_#{user.id}", target: ["rb_export_#{report.id}", size].compact.join("_"),
                                                                          partial: "report_builder/export_button",
                                                                          locals: { report: report, state: state, document: document, size: size })
    end
  end

  # Worked examples R4, R4-X — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def owner_still_belongs?(user, entity)
    [user.entity_id, user.advisor_entity_id].compact.include?(entity.id) ||
      (user.entity_type == "Group Company" && user.entity&.child_ids&.include?(entity.id)) ||
      InvestorAdvisor.exists?(user_id: user.id, entity_id: entity.id)
  end
end
