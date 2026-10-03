# Converts legacy Doc Questions into Document Checks — run by support before the Doc Questions
# retirement deploy, per environment (IN and US separately).
#
#   bin/rails doc_checks:convert_doc_questions                  # dry run, every entity with questions
#   bin/rails doc_checks:convert_doc_questions ENTITY_ID=841    # dry run, one entity
#   bin/rails doc_checks:convert_doc_questions EXECUTE=1        # convert (idempotent)
#
# Prints, per entity, what converts (look for → field) and what doesn't (with the reason). Nothing is
# written without EXECUTE=1.
# See openspec/changes/document-checks/design.md (Converting the legacy questions). Worked examples H10, H11, X9.
namespace :doc_checks do
  desc "Convert legacy Doc Questions into Document Checks (dry run unless EXECUTE=1)"
  task convert_doc_questions: :environment do
    execute = ENV["EXECUTE"] == "1"
    entity_ids = ENV["ENTITY_ID"].present? ? [ENV["ENTITY_ID"].to_i] : DocQuestion.where(for_class: "InvestorKyc").distinct.pluck(:entity_id)
    puts(execute ? "Converting Doc Questions (EXECUTE=1)" : "DRY RUN — nothing will be written (set EXECUTE=1 to convert)")

    Entity.where(id: entity_ids).find_each do |entity|
      report = DocChecks::LegacyConverter.call(entity:, execute:)
      puts "\n== #{entity.name} (##{entity.id}): #{report[:converted].size} convert, #{report[:not_converted].size} don't"
      report[:converted].each do |row|
        puts "  ✓ ##{row[:question_id]} #{row[:document]} · #{row[:action]} · #{row[:look_for]} → #{row[:field] || '(yes-no question)'}"
      end
      report[:not_converted].each do |row|
        puts "  ✗ ##{row[:question_id]} #{row[:question]} — #{row[:reason]}"
      end
    end
  end
end
