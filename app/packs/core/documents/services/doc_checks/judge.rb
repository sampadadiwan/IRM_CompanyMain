# Decides one check's outcome from what the AI read. Pure: it reads the record through the registry entry
# and returns a pending write instead of writing — the run applies all writes at the end.
#
#   DocChecks::Judge.call(check:, reading:, record:, entry:)
#   => { outcome:, note:, doc_value:, record_value:, explanation:, write: [field, value] or nil }
#
# outcome is "ok" or the reason the item needs attention (see DocCheckResult::OUTCOMES). For "ok" the note
# says which kind (filled / kept / replaced / matches / yes).
# See openspec/changes/document-checks/design.md (card ⑥ Judge). Worked examples H3, E8–E11, E16–E18.
module DocChecks
  class Judge
    # Stripped before comparing, together with all whitespace
    PUNCTUATION = %r{[.,\-/()'"`]}
    YES = %w[yes true y].freeze

    def self.call(check:, reading:, record:, entry:)
      new(check:, reading: reading || {}, record:, entry:).call
    end

    def initialize(check:, reading:, record:, entry:)
      @check = check
      @reading = reading
      @record = record
      @entry = entry
    end

    def call
      return question if @check.question?

      # The check's field was removed from the record's form after setup. Worked example E16.
      field = @entry.field(@record.entity, @check.field_name)
      return result("field_missing") unless field

      @check.fill_in? ? fill_in(field) : compare(field)
    end

    # Normalised for comparing: case, whitespace and punctuation ignored; for names and addresses the
    # word order too ("RAO ASHA" = "Asha Rao"). Worked examples E8, E9.
    def self.normalise(value, loose: false)
      words = value.to_s.downcase.gsub(PUNCTUATION, " ").split
      words = words.sort if loose
      words.join
    end

    private

    def found?
      @reading["found"] == true && doc_value.present?
    end

    def doc_value
      @reading["value"].to_s.strip
    end

    def explanation
      @reading["explanation"].to_s.presence
    end

    def fill_in(field)
      return result("not_found") unless found?

      value = parse_if_date(field, doc_value)
      return result("bad_date", doc_value:) if value == :bad_date

      current = @entry.read(@record, field)
      shown = display(value)
      # Empty field (or Replace on): fill it. Worked example H3.
      if current.blank? || @check.replace_existing
        note = current.blank? ? "filled" : "replaced"
        return result("ok", note:, doc_value: shown, record_value: display(current), write: [field, value])
      end

      # A value is already there: keep it, saying what the document says if it differs. Worked example E10.
      result("ok", note: "kept", doc_value: shown, record_value: display(current))
    end

    def compare(field)
      return result("not_found") unless found?

      current = @entry.read(@record, field)
      return result("kyc_blank", doc_value:) if current.blank?

      same = if field.date?
               parsed = parse_if_date(field, doc_value)
               parsed != :bad_date && parsed == parse_if_date(field, current)
             else
               self.class.normalise(doc_value, loose: field.loose?) == self.class.normalise(current, loose: field.loose?)
             end
      # Worked examples E8, E9 (match), E18 (mismatch)
      result(same ? "ok" : "mismatch", note: ("matches" if same), doc_value:, record_value: display(current))
    end

    # A yes-no question: anything other than a clear yes counts as no. Worked example E17.
    def question
      answer = YES.include?(doc_value.downcase) ? "yes" : "no"
      return result("ok", note: "yes", doc_value: answer.capitalize) if answer == @check.expected_answer

      result("unexpected_answer", doc_value: answer.capitalize)
    end

    def parse_if_date(field, value)
      return value unless field.date?
      return value if value.is_a?(Date)

      @entry.parse_date(value)
    rescue Error::BadValue
      :bad_date
    end

    def display(value)
      value.is_a?(Date) ? value.iso8601 : value.to_s
    end

    def result(outcome, note: nil, doc_value: self.doc_value, record_value: nil, write: nil)
      { outcome:, note:, doc_value: doc_value.to_s.presence, record_value: record_value.to_s.presence,
        explanation:, write: }
    end
  end
end
