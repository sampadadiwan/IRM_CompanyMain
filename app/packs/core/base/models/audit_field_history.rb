# Pivots a bounded set of Audit records (all belonging to one auditable
# record — see the `@single_record_scope` guard in AuditsController#index
# and AuditTrail#field_history) into the "Field History" view: one row per
# attribute, one column per moment any attribute changed, cell = the value
# it changed to and who changed it.
#
# Deliberately takes a plain audits enumerable rather than a scope/relation —
# callers are responsible for making sure it's bounded to a single record's
# history before building this (an unscoped table-wide list would produce a
# meaningless pivot, mixing different records' "city" etc. into one row).
class AuditFieldHistory
  def initialize(audits, changes_for: ->(audit) { audit.audited_changes })
    @audits = audits
    @changes_for = changes_for
  end

  # One row per (field, change) across the given audits, oldest first.
  def entries
    @entries ||= @audits.each_with_object([]) do |audit, rows|
      AuditChangeFlattener.call(@changes_for.call(audit)).each do |row|
        rows << {
          key: row[:key],
          label: row[:label],
          time: audit.created_at,
          user: audit.user,
          value: row[:new].presence || row[:old],
        }
      end
    end.sort_by { |row| row[:time] }
  end

  # Distinct {key, label} options for the field-picker, alphabetical by label.
  def available_fields
    entries.map { |row| [row[:key], row[:label]] }.uniq.sort_by { |_, label| label }
  end

  # Distinct moments at which any field changed, oldest first — the column
  # headers of the pivoted table.
  def timestamps
    entries.map { |row| row[:time] }.uniq.sort
  end

  # field_key => { timestamp => { value:, user: } }
  def matrix
    @matrix ||= entries.each_with_object(Hash.new { |h, k| h[k] = {} }) do |row, m|
      m[row[:key]][row[:time]] = { value: row[:value], user: row[:user] }
    end
  end

  def any?
    entries.any?
  end
end
