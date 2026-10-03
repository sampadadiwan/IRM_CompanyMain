# Deploy 2 of Document Checks, step 1 of 2: converts every fund's KYC Doc Questions into Document Checks, so
# the deploy needs no manual step. Runs just before 20261005090000_retire_doc_questions, which drops the
# legacy tables once every question is converted or logged as not converted.
#
# Each question becomes a check (linked by doc_checks.legacy_doc_question_id) or is logged with its reason;
# questions for other record types are logged too. The per-entity report — what converted, what didn't and
# why — is printed in the deploy output and the Rails log: it is Support's list of checks to set up by hand,
# since the log table is dropped by the next migration.
# Safe to re-run (converted questions are skipped); does nothing where doc_questions is already gone.
# See openspec/changes/archive/2026-10-03-document-checks/design.md (Converting the legacy questions).
# Worked examples H10, H11, X9, R6.
class ConvertDocQuestions < ActiveRecord::Migration[8.1]
  def up
    # Nothing to convert on a fresh database or one already past the retirement
    return unless table_exists?(:doc_questions)

    converter = DocChecks::LegacyConverter
    [converter::Question, converter::ConversionLog, DocCheck].each(&:reset_column_information)

    # Every fund with KYC questions, one report each
    entity_ids = converter::Question.where(for_class: converter::RECORD_TYPE).distinct.pluck(:entity_id)
    Entity.where(id: entity_ids).find_each do |entity|
      report = converter.call(entity:, execute: true)
      announce_report(entity, report)
    end

    # Questions for other record types: logged, so nothing unreviewed is left for the drop's guard
    others = converter.log_other_record_types!
    log_line("Logged #{others} Doc Questions for other record types as not converted") if others.positive?
  end

  # The checks it created are ordinary checks now; nothing to undo
  def down; end

  private

  def announce_report(entity, report)
    log_line("#{entity.name} (##{entity.id}): #{report[:converted].size} converted, #{report[:not_converted].size} not converted")
    report[:converted].each do |row|
      log_line("  ✓ ##{row[:question_id]} #{row[:document]} · #{row[:action]} · #{row[:look_for]} → #{row[:field] || '(yes-no question)'}")
    end
    report[:not_converted].each do |row|
      log_line("  ✗ ##{row[:question_id]} #{row[:question]} — #{row[:reason]}")
    end
  end

  # The deploy output and the Rails log
  def log_line(text)
    say(text)
    Rails.logger.info("[ConvertDocQuestions] #{text}")
  end
end
