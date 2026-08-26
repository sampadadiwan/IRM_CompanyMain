# Flattens a single Audit's `audited_changes` into real field-level diffs.
# "json_fields" holds the whole custom-fields blob before/after (not a diff),
# so it gets expanded into one entry per key that actually changed. A
# nil/"" pair on either side is treated as no change (Audited records one
# whenever a form submits an empty string for an already-blank field).
#
# Shared by the audit-trail event view (layouts/_audit_event_row) and the
# per-field history view (AuditTrail component) so both agree on what counts
# as "a change".
class AuditChangeFlattener
  def self.call(audited_changes)
    new(audited_changes).call
  end

  def initialize(audited_changes)
    @audited_changes = audited_changes || {}
  end

  def call
    rows = []
    @audited_changes.each do |key, value|
      if key == "json_fields" && value.is_a?(Array)
        rows.concat(json_fields_rows(value))
      elsif value.is_a?(Array)
        next if value[0].presence == value[1].presence

        rows << { key: key, label: key.humanize, old: value[0], new: value[1] }
      else
        rows << { key: key, label: key.humanize, old: nil, new: value }
      end
    end
    rows
  end

  private

  def json_fields_rows(value)
    old_json = parse_json(value[0])
    new_json = parse_json(value[1])

    (old_json.keys | new_json.keys).filter_map do |field_key|
      old_val, new_val = old_json[field_key], new_json[field_key]
      next if old_val.presence == new_val.presence

      { key: field_key, label: Json2table.to_human(field_key), old: old_val, new: new_val }
    end
  end

  def parse_json(value)
    return value || {} unless value.is_a?(String)

    JSON.parse(value)
  rescue JSON::ParserError
    {}
  end
end
