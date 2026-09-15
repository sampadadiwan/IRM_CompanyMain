# frozen_string_literal: true

# Exports FAQ entries to an .xlsx spreadsheet and imports one back.
#
# Production is the master copy of FAQs; the spreadsheet is how support edits in bulk and how
# a copy is kept in git or loaded into another environment. Rows are matched on ID when present,
# otherwise on Guide + Question. Rows with no ID and a new question create entries. Nothing is
# deleted by an import: set Status to "archived" to retire an entry.
class FaqSpreadsheet
  HEADERS = ["ID", "Guide", "Group", "Position", "Question", "Answer", "Keywords", "Audience", "Status",
             "Last Verified", "Needs Verification"].freeze

  ImportResult = Data.define(:created, :updated, :unchanged, :errors) do
    # @return [String] one-line summary for a flash message or rake output
    def summary
      "#{created} created, #{updated} updated, #{unchanged} unchanged, #{errors.size} rows with errors"
    end
  end

  # @param scope [ActiveRecord::Relation<FaqEntry>]
  # @return [String] xlsx file contents
  def self.export(scope)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "FAQs") do |sheet|
      sheet.add_row HEADERS
      scope.ordered.find_each(batch_size: 500) do |e|
        sheet.add_row [e.id, e.guide_key, e.faq_group, e.position, e.question, e.answer, e.keywords, e.audience,
                       e.status, e.last_verified_at&.to_date&.iso8601, e.needs_verification ? "Yes" : "No"],
                      types: [:integer] + ([:string] * 10)
      end
    end
    package.to_stream.read
  end

  # @param path [String] path to an .xlsx file
  # @param user [User, nil] recorded as creator/updater
  # @return [ImportResult]
  def self.import(path, user:)
    new(user).import(path)
  end

  # @param user [User, nil]
  def initialize(user)
    @user = user
  end

  # @param path [String]
  # @return [ImportResult]
  def import(path)
    counts = Hash.new(0)
    errors = []
    sheet = Roo::Spreadsheet.open(path.to_s, extension: :xlsx).sheet(0)
    headers = sheet.row(1).map { |h| h.to_s.strip }
    missing = HEADERS.first(9) - headers
    raise ArgumentError, "Missing columns: #{missing.join(', ')}" if missing.any?

    (2..sheet.last_row.to_i).each do |row_number|
      row = headers.zip(sheet.row(row_number)).to_h
      next if row.values_at("Guide", "Question", "Answer").all?(&:blank?)

      outcome, messages = import_row(row)
      counts[outcome] += 1 if outcome
      errors << "Row #{row_number}: #{messages.to_sentence}" if messages.present?
    end
    ImportResult.new(created: counts[:created], updated: counts[:updated], unchanged: counts[:unchanged], errors: errors)
  end

  private

  # @param row [Hash{String => Object}]
  # @return [Array(Symbol, Array<String>)] outcome and error messages
  def import_row(row)
    entry = find_entry(row)
    return [nil, ["no FAQ with ID #{row['ID']}"]] if entry.nil?

    new_record = entry.new_record?
    entry.assign_attributes(
      guide_key: row["Guide"].to_s.strip, faq_group: row["Group"].to_s.strip, question: row["Question"].to_s.strip,
      answer: row["Answer"].to_s.strip, keywords: row["Keywords"].to_s.strip.presence,
      audience: row["Audience"].to_s.strip.presence || "signed_in"
    )
    entry.position = row["Position"].to_i if row["Position"].present?
    status = row["Status"].to_s.strip.presence || "draft"
    return [:unchanged, []] if !new_record && !entry.changed? && entry.status == status

    entry.created_by ||= @user
    entry.updated_by = @user
    saved = status == "published" && !entry.published? ? entry.publish!(@user) : entry.tap { |e| e.status = status }.save
    if saved
      [new_record ? :created : :updated, []]
    else
      [nil, entry.errors.full_messages]
    end
  end

  # @return [FaqEntry, nil] nil when an ID is given but not found
  def find_entry(row)
    return FaqEntry.find_by(id: row["ID"].to_i) if row["ID"].present?

    FaqEntry.find_or_initialize_by(guide_key: row["Guide"].to_s.strip, question: row["Question"].to_s.strip)
  end
end
