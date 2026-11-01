# Deletes "Describe it" drafts nobody has touched for 7 days. Saved reports are
# never drafts (saving clears the category), so they are never touched.
# Runs daily from sidekiq-cron (config/initializers/sidekiq.rb).
# Worked example E10 — openspec/changes/report-builder-assistant/business-rules.md
class ReportDraftCleanupJob < ApplicationJob
  queue_as :low

  KEEP_FOR = 7.days

  def perform
    Report.where(category: ReportBuilder::Assistant::DRAFT_CATEGORY, report_builder: true)
          .where(updated_at: ...KEEP_FOR.ago)
          .find_each(&:destroy)
  end
end
