# ① Loads a pack JSON (db/seeds/compliance/*.json) as the next version of a CapHive pack.
# Publishing from a file is a CapHive ops action; the file records the counsel review fields.
class CompliancePackLoader
  def self.call(data, publish: false, user: nil)
    pack_attrs = data["pack"]
    pack = CompliancePack.find_or_create_by!(entity_id: nil, name: pack_attrs["name"]) do |p|
      p.regime = pack_attrs["regime"]
      p.locked = pack_attrs["locked"] != false
      p.time_zone = pack_attrs["time_zone"].presence || "Asia/Kolkata"
    end
    v = data["version"] || {}
    version = pack.versions.create!(version_no: (pack.versions.maximum(:version_no) || 0) + 1, definition: data["definition"],
                                    corrects_version_id: v["corrects_version_id"])
    return version unless publish

    version.mark_tested!(user)
    version.publish!(user:, attrs: { effective_from: Date.parse(v["effective_from"]), applicability: v["applicability"] || "all",
                                     applicability_date: v["applicability_date"] && Date.parse(v["applicability_date"]),
                                     transition_ends_on: v["transition_ends_on"] && Date.parse(v["transition_ends_on"]),
                                     allows_early_adoption: v["allows_early_adoption"] || false,
                                     counsel_reviewer: v["counsel_reviewer"], counsel_reviewed_on: v["counsel_reviewed_on"] && Date.parse(v["counsel_reviewed_on"]) }.compact) ||
      raise(ActiveRecord::RecordInvalid, version)
    version
  end
end
