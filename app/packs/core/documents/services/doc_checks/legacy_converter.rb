# Turns an entity's legacy Doc Questions (for_class InvestorKyc) into Document Checks. Run by the deploy, in
# migration 20261005080000_convert_doc_questions, just before 20261005090000_retire_doc_questions drops the
# legacy tables — so no environment needs a manual step.
#
# Nothing is guessed: a question whose document isn't on the entity's KYC lists, whose field can't be
# resolved, or whose field is already used on that document is reported as not converted and logged (so the
# retirement migration knows it was reviewed). Idempotent via doc_checks.legacy_doc_question_id.
# Self-contained: the DocQuestion and DocCheckConversionLog models are gone, so the two legacy tables are
# read and written through the small classes below.
#
#   DocChecks::LegacyConverter.call(entity:, execute: false)
#   => { converted: [{ question_id:, document:, look_for:, action:, field: }], not_converted: [{ question_id:, question:, reason: }] }
#
# Dead once every environment has run the conversion migration; remove it then.
# See openspec/changes/archive/2026-10-03-document-checks/design.md (Converting the legacy questions).
# Worked examples H10, H11, X9.
module DocChecks
  class LegacyConverter
    FIELD_HINT = /field\s+([\w ]+)/i
    LEADING_EXTRACT = /\A\s*extract\s+(?:the\s+)?(?:field\s+)?/i
    # The only record type the old feature checked documents for
    RECORD_TYPE = "InvestorKyc".freeze

    # The legacy tables, without the deleted models
    class Question < ApplicationRecord
      self.table_name = "doc_questions"
    end

    class ConversionLog < ApplicationRecord
      self.table_name = "doc_check_conversion_logs"
    end

    def self.call(entity:, execute: false)
      new(entity:, execute:).call
    end

    # Questions for any other record type were never checked by the old feature: logged as not converted, so
    # the retirement guard sees them reviewed. Returns how many were logged.
    def self.log_other_record_types!
      others = Question.where.not(for_class: RECORD_TYPE).or(Question.where(for_class: nil))
      others.find_each do |question|
        ConversionLog.find_or_initialize_by(doc_question_id: question.id)
                     .update!(entity_id: question.entity_id, reason: "Only KYC Doc Questions convert (for #{question.for_class.inspect})")
      end
      others.count
    end

    def initialize(entity:, execute:)
      @entity = entity
      @execute = execute
      @entry = Registry.for(RECORD_TYPE)
      @fields = @entry.fields_for(entity)
      @names = @entry.document_names(entity)
    end

    def call
      report = { converted: [], not_converted: [] }
      # Fields already used per document, including checks converted earlier in this same run
      used = DocCheck.where(entity: @entity, record_type: RECORD_TYPE).pluck(:document_name, :field_name)
                     .group_by { |doc, _| doc.downcase }.transform_values { |rows| rows.filter_map(&:last).to_set }
      Question.where(entity_id: @entity.id, for_class: RECORD_TYPE).order(:id).find_each do |question|
        # Converted on an earlier run: report it again, change nothing (H11)
        if (existing = DocCheck.find_by(legacy_doc_question_id: question.id))
          report[:converted] << row_for(question, existing)
          next
        end

        outcome = convert(question, used)
        # Anything else the check itself refuses (e.g. the same look-for twice on a card) is reported too
        outcome = { reason: outcome[:check].errors.full_messages.to_sentence } if outcome[:check] && !outcome[:check].valid?
        if outcome[:check]
          used[outcome[:check].document_name.downcase] = (used[outcome[:check].document_name.downcase] || Set.new) << outcome[:check].field_name if outcome[:check].field_name
          outcome[:check].save! if @execute
          report[:converted] << row_for(question, outcome[:check])
        else
          log_not_converted(question, outcome[:reason]) if @execute
          report[:not_converted] << { question_id: question.id, question: question.question.to_s.truncate(80), reason: outcome[:reason] }
        end
      end
      report
    end

    private

    def convert(question, used)
      # "$full_name" asked the AI to compare with the record — that is now a Compare check, set up by a person
      return { reason: "Uses a $placeholder — set it up as a Compare check instead" } if question.question.to_s.match?(/\$\w+/)

      document_name = @names.find { |name| name.casecmp?(question.document_name.to_s.strip) }
      return { reason: "Document #{question.document_name.inspect} is not on the KYC document lists" } unless document_name

      action = fill_in?(question) ? "fill_in" : "question"
      look_for = look_for_of(question)
      check = DocCheck.new(entity: @entity, record_type: RECORD_TYPE, document_name:, action:, look_for:,
                           tip: question.question.to_s.squish.truncate(255), legacy_doc_question_id: question.id,
                           position: DocCheck.where(entity: @entity, document_name:).count)
      return { check: } if action == "question"

      wanted = wanted_field(question, look_for)
      field = resolve_field(wanted)
      return { reason: "Field #{wanted} not found" } unless field
      return { reason: "Field #{field.name} is already used on this document" } if used[document_name.downcase]&.include?(field.name)

      check.field_name = field.name
      { check: }
    end

    # Extraction questions, and Validation ones that ask to extract, fill a field
    def fill_in?(question)
      question.qtype.to_s.casecmp?("Extraction") || question.question.to_s.match?(/\A\s*extract/i)
    end

    def look_for_of(question)
      question.question.to_s.squish.sub(LEADING_EXTRACT, "").sub(/[.?]\z/, "").truncate(100).presence || question.question.to_s.truncate(100)
    end

    # "Extract to field pan" → "pan"; otherwise the look-for itself ("Address" → "address")
    def wanted_field(question, look_for)
      hint = question.response_hint.to_s[FIELD_HINT, 1]
      (hint.presence || look_for).squish.parameterize.underscore
    end

    # The old feature's rule (parameterize.underscore), matched case-insensitively to an allowed field
    def resolve_field(wanted)
      @fields.find { |f| f.name.parameterize.underscore.casecmp?(wanted) }
    end

    def row_for(question, check)
      { question_id: question.id, document: check.document_name, look_for: check.look_for, action: check.action, field: check.field_name }
    end

    def log_not_converted(question, reason)
      ConversionLog.find_or_initialize_by(doc_question_id: question.id).update!(entity_id: @entity.id, reason: reason.to_s.truncate(255))
    end
  end
end
