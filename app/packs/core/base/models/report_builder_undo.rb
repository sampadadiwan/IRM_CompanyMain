# One-step Undo for removals in the Report Builder (a column, or related data
# with its columns). The set-up from before the removal is kept in
# reports.template["undo"] with a digest of the set-up just after it; Undo puts
# it back only within 10 minutes and only if nothing has changed since.
#
#   template["undo"] = { "token", "at", "label",
#                        "template"     => definition before the removal (never a nested "undo"),
#                        "gvps"         => attributes of the removed columns,
#                        "after_digest" => digest of the definition after the removal }
#
# Worked examples H11, H12, E12, E13 — openspec/changes/report-builder-live-builder/business-rules.md
class ReportBuilderUndo
  WINDOW = 10.minutes
  DIGEST_KEYS = %w[root_model joins aggregates root_filters sort formulas group_rows_by currency].freeze
  GVP_ATTRIBUTES = %w[name key label sequence data_type selected derived_field alignment custom_grid_view_id].freeze

  TOO_LATE = "Too late to undo — removals can be undone for 10 minutes".freeze
  CHANGED  = "Too late to undo — the report has changed since".freeze

  class << self
    # Call after the removal: `before` is the template as it was, `removed` the
    # GridViewPreference rows that were deleted (read before deleting them).
    def snapshot!(report, label:, before:, removed:)
      token = SecureRandom.hex(8)
      report.reload
      undo = {
        "token" => token,
        "at" => Time.current.iso8601,
        "label" => label,
        "template" => before.deep_stringify_keys.except("undo"),
        "gvps" => removed.map { |gvp| gvp.attributes.slice(*GVP_ATTRIBUTES) },
        "after_digest" => definition_digest(report)
      }
      report.update!(template: (report.template || {}).merge("undo" => undo))
      token
    end

    # [:ok, label] or [:refused, reason]. Locks the report so a double click
    # restores once; the snapshot is cleared in the same transaction.
    def restore!(report, token, now: Time.current)
      Report.transaction do
        report.lock!
        undo = (report.template || {})["undo"]
        # A missing or replaced snapshot means another change came after it (E13)
        return [:refused, CHANGED] if undo.blank? || undo["token"] != token.to_s
        return [:refused, TOO_LATE] if Time.zone.parse(undo["at"]) < now - WINDOW
        return [:refused, CHANGED] if definition_digest(report) != undo["after_digest"]

        report.update!(template: undo["template"])
        # acts_as_list closed the gaps on removal; inserting in ascending order
        # at the old positions puts every column back where it was (H11)
        undo["gvps"].sort_by { |attrs| attrs["sequence"].to_i }.each do |attrs|
          report.grid_view_preferences.create!(attrs.merge("entity_id" => report.entity_id))
        end
        [:ok, undo["label"]]
      end
    end

    # Any other change ends the chance to undo
    def drop!(report)
      template = report.reload.template || {}
      report.update!(template: template.except("undo")) if template.key?("undo")
    end

    # What a later change would alter: the definition and the column list
    def definition_digest(report)
      definition = (report.template || {}).deep_stringify_keys.slice(*DIGEST_KEYS)
      columns = report.grid_view_preferences.reorder(:sequence, :id).pluck(:key, :label, :sequence)
      Digest::SHA256.hexdigest([definition, columns].to_json)
    end
  end
end
