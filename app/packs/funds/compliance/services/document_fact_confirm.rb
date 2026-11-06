# ⑦ A compliance editor confirms a document's facts — as read, or corrected — or enters them by hand.
# Only confirmed facts count in a run (E66). Every change is audited with the person and date, which is
# what the fact history shows ("AI read ₹1.50 cr → Meera set ₹15.00 cr", E67).
# Manual entry (H43, X45): when reading is off or a document could not be read, the facts are entered and
# confirmed in one step; nothing is sent to AI.
# Worked examples H43, E67, X45 — openspec/changes/fund-compliance-monitoring/business-rules.md
class DocumentFactConfirm
  Result = Struct.new(:reading, :error, :notice, keyword_init: true)

  # values: {"amount_approved" => "150000000"}; only keys of this reading's facts are used
  def self.call(reading:, user:, values: {})
    values = values.to_h.stringify_keys
    facts = reading.document_facts.to_a
    errors = parse_errors(facts.to_h { |f| [f.fact_key, f.value_type] }, values, facts.index_by(&:fact_key))
    return Result.new(reading:, error: errors.to_sentence) if errors.any?

    Audited.audit_class.as_user(user) do
      DocumentFact.transaction do
        facts.each do |fact|
          raw = values[fact.fact_key]
          fact.confirm!(user, new_value: raw.nil? || same?(fact, raw) ? :unchanged : raw)
        end
      end
    end
    Result.new(reading:, notice: "#{facts.size} fact#{'s' if facts.size != 1} confirmed")
  end

  # H43: facts entered by hand for a document (reading off, or an unreadable scan)
  def self.manual(document:, input_key:, user:, values:)
    input = ComplianceDocumentInputs.find(document.entity, input_key)
    return Result.new(error: "No pack asks for facts from this document") if input.nil? || input.facts.empty?

    values = values.to_h.stringify_keys
    types = input.facts.to_h { |f| [f["key"], f["type"]] }
    errors = parse_errors(types, values, {})
    return Result.new(error: errors.to_sentence) if errors.any?

    reading = nil
    Audited.audit_class.as_user(user) do
      DocumentReading.transaction do
        reading = DocumentReading.find_or_initialize_by(document_id: document.id, input_key: input.key,
                                                        file_checksum: DocumentReading.checksum_for(document), facts_signature: input.signature)
        reading.entity_id ||= document.entity_id
        reading.status = "manual" unless reading.status == "read"
        reading.save!
        input.facts.each do |f|
          fact = reading.document_facts.find_or_initialize_by(fact_key: f["key"])
          fact.assign_attributes(entity_id: document.entity_id, value_type: f["type"], source: fact.new_record? ? "manual" : fact.source)
          fact.value = DocumentFact.normalize(f["type"], values[f["key"]]) if values.key?(f["key"])
          fact.status = "confirmed"
          fact.confirmed_by = user
          fact.confirmed_at = Time.current
          fact.save!
        end
      end
    end
    Result.new(reading:, notice: "Facts entered and confirmed")
  end

  # Typed values that do not parse are refused with the fact's name
  def self.parse_errors(types, values, facts)
    values.filter_map do |key, raw|
      type = types[key]
      next if type.nil? || raw.to_s.strip.empty? || type == "text"
      next unless DocumentFact.normalize(type, raw).nil?

      "#{facts[key]&.fact_key&.humanize || key.humanize}: enter a valid #{type == 'yes_no' ? 'yes or no' : type}"
    end
  end

  def self.same?(fact, raw)
    DocumentFact.normalize(fact.value_type, raw) == fact.value
  end
end
