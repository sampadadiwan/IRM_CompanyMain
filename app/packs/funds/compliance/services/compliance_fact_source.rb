# ④ The catalogue's "facts" source: what each document says, as far as a content check may use it.
# Only confirmed facts count (E66). For each document it answers either "usable, with these values" or a
# Needs review reason a person can act on:
#   no reading, reading off       → "Needs review — reading not enabled"      (E74)
#   queued / capped               → "Needs review — waiting to be read"       (E75)
#   failed, nothing entered       → "Needs review — could not read document"  (X45, X46)
#   a needed fact never read      → "Needs review — new fact in v2"           (E130)
#   a needed fact not found       → "Needs review — Conflicts not found in document" (E69)
#   a needed fact unconfirmed     → "Needs review — AI-read, unconfirmed"     (E66)
# Facts belong to the document's newest reading, so they follow the document to another record (E129).
# Read-only; one query for the readings (facts preloaded).
# Worked examples E66, E69, E74, E75, E129, E130, X45 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceFactSource
  State = Struct.new(:usable, :problem, :facts, keyword_init: true)

  def initialize(entity:, input_key:, document_ids:, version:, setup:)
    @input_key = input_key.to_s
    @version = version
    @declared = ComplianceDocumentInputs.version_facts(version, input_key)
    @reading_on = DocumentReadingQueue.enabled?(setup, input_key)
    @readings = document_ids.empty? ? {} : DocumentReading.current_for(document_ids, @input_key)
    @entity = entity
  end

  def label(fact_key)
    f = @declared.detect { |d| d["key"] == fact_key }
    f&.dig("label").presence || fact_key.to_s.humanize
  end

  # needed: the fact keys the rule reads
  def state(document_id, needed)
    reading = @readings[document_id]
    return review(@reading_on ? "waiting to be read" : "reading not enabled") if reading.nil?
    return review("waiting to be read") if reading.waiting?

    facts = reading.facts_by_key
    return review("could not read document") if reading.status == "failed" && facts.empty?
    # E130: the version declares a fact this reading never had
    return review("new fact in #{@version.label}") if (@declared.pluck("key") - facts.keys).any?

    needed.each do |key|
      fact = facts[key]
      return review("#{label(key)} not found in document") if fact.nil? || (fact.not_found? && !fact.confirmed?)
    end
    return review("AI-read, unconfirmed") if needed.any? { |k| !facts[k].confirmed? }

    State.new(usable: true, facts: needed.index_with { |k| facts[k].typed_value })
  end

  private

  def review(reason)
    State.new(usable: false, problem: "Needs review — #{reason}")
  end
end
