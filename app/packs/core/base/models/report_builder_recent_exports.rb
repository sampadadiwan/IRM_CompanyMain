# The last few Excel files exported from one Report Builder report, for the
# report page's "Recent exports" list. The export job saves each file as a
# Document owned by the report and tagged "Generated"; only those the user may
# open are listed, newest first.
#
# Worked examples H3, E1, E2 — openspec/changes/report-builder-delivery/business-rules.md
class ReportBuilderRecentExports
  # Policy checks are per document: look at a bounded batch, so a few hidden
  # ones don't empty the list and a long history doesn't cost a check each
  BATCH = 25

  def self.for(report, user, limit: 5)
    # Only this report's own exports (E2), newest first (H3)
    candidates = Document.where(owner: report, owner_tag: "Generated")
                         .includes(:user, :folder)
                         .order(created_at: :desc, id: :desc)
                         .limit(BATCH)

    # Only files this user may open
    candidates.select { |doc| DocumentPolicy.new(user, doc).show? }.first(limit)
  end
end
