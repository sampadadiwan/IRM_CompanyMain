# U12 / R159: writes plain-words check descriptions into pack versions that were published before
# descriptions existed — an approved, text-only exception to "published versions are never edited".
#
# For every published version of a pack named in `sources`, the version's definition minus descriptions
# must equal a source definition minus descriptions; only then are that source's descriptions written,
# key by key. Any other difference (a limit, a filter, a check added or removed) means the version is
# not the one the file describes, so it is skipped and reported, never touched (X94). The write is a
# single update_column — no callbacks, so a published version's test stamp is not cleared — plus one
# Audit row naming U12.
#
#   sources = { "SEBI — AIF" => [definition_hash, ...], "Demo Fund — LPA rules" => [definition_hash] }
#
# Worked examples E194, X94 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDescriptionBackfill
  Line = Struct.new(:pack, :version, :status, :checks, keyword_init: true) do
    def to_s
      case status
      when :fill then "#{pack} #{version}: #{checks} check#{'s' unless checks == 1} to describe"
      when :done then "#{pack} #{version}: already described"
      else "#{pack} #{version}: rules differ from the seed file — not touched"
      end
    end
  end

  def self.call(sources:, execute: false)
    new(sources, execute).call
  end

  def initialize(sources, execute)
    @sources = sources
    @execute = execute
  end

  def call
    CompliancePackVersion.includes(:compliance_pack).where(status: "published").order(:compliance_pack_id, :version_no).filter_map do |version|
      candidates = @sources[version.compliance_pack.name]
      next if candidates.blank?

      line_for(version, candidates)
    end
  end

  # Definition with every check's and duty's description removed — what must match before writing
  def self.without_descriptions(definition)
    d = definition.deep_dup
    %w[checks duties].each { |k| Array(d[k]).each { |c| c.delete("description") } }
    d
  end

  private

  def line_for(version, candidates)
    current = version.definition_hash
    bare = self.class.without_descriptions(current)
    source = candidates.find { |c| self.class.without_descriptions(c) == bare }
    label = version.label
    return Line.new(pack: version.compliance_pack.name, version: label, status: :differs) unless source

    updated = with_descriptions(current, source)
    count = Array(updated["checks"]).zip(Array(current["checks"])).count { |n, o| n["description"] != o["description"] }
    return Line.new(pack: version.compliance_pack.name, version: label, status: :done) if count.zero?

    write!(version, current, updated) if @execute
    Line.new(pack: version.compliance_pack.name, version: label, status: :fill, checks: count)
  end

  def with_descriptions(current, source)
    texts = Array(source["checks"]).to_h { |c| [c["key"], c["description"]] }
    updated = current.deep_dup
    Array(updated["checks"]).each { |c| c["description"] = texts[c["key"]] if texts[c["key"]].present? }
    updated
  end

  def write!(version, before, after)
    # Belt and braces: nothing but descriptions may differ (X94)
    raise "Refusing to change rules of #{version.compliance_pack.name} #{version.label}" unless
      self.class.without_descriptions(before) == self.class.without_descriptions(after)

    CompliancePackVersion.transaction do
      version.update_column(:definition, after)
      Audit.create!(auditable: version, action: "update", audited_changes: { "definition" => [before, after] },
                    comment: "Check descriptions backfilled (U12, R159) — text only, rules unchanged")
    end
  end
end
