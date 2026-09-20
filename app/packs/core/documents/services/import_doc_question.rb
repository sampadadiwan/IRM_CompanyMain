# frozen_string_literal: true

# Imports DocQuestions - the questions the LLM asks of an uploaded document,
# either to validate it (Yes/No) or to extract a value from it.
#
# The columns mirror the DocQuestions download (views/doc_questions/index.xlsx.axlsx)
# so a downloaded sheet can be edited and uploaded back. The download's "Id" is what
# makes that round trip work: a row carrying one updates the question it came from,
# so an edit to the question text is an edit and not a second question. A row with no
# Id creates a question, and refuses to create one that already exists.
class ImportDocQuestion < ImportUtil
  # DocQuestion has no custom fields, so drop the step that would create them
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Question", "Type", "For", "Document Name", "Tags", "Extract To"].freeze

  # The download adds this; it is not importable. "Id" is deliberately not ignored - see above.
  IGNORE_HEADERS = %w[Created].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    IGNORE_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    question = cell(user_data, "Question", required: true)
    qtype = parse_qtype(cell(user_data, "Type", required: true))
    for_class = parse_for_class(cell(user_data, "For", required: true))
    document_name = cell(user_data, "Document Name").presence
    tags = cell(user_data, "Tags").presence
    response_hint = cell(user_data, "Extract To").presence

    # The model enforces this too, but its message ("Name or Tags must be present")
    # lands on two attributes and reads oddly in the results sheet
    raise "Document Name or Tags must be specified" if document_name.blank? && tags.blank?

    attributes = { question:, qtype:, for_class:, document_name:, tags:, response_hint: }
    id = cell(user_data, "Id").presence

    id.present? ? update_question(import_upload, id, attributes) : create_question(import_upload, attributes)

    true
  end

  private

  def update_question(import_upload, id, attributes)
    doc_question = DocQuestion.where(entity_id: import_upload.entity_id, id:).first
    raise "No question found with Id #{id}. Leave Id blank to create a new question." if doc_question.nil?

    # import_upload_id is deliberately left alone. ImportUpload#imported_data is
    # "rows this upload created", and it is what Delete Imported Data destroys -
    # re-parenting an edited row onto this upload would put questions it merely
    # corrected (or ones entered by hand) in the blast radius of that button.
    doc_question.update!(attributes)
  end

  def create_question(import_upload, attributes)
    if duplicate?(import_upload, attributes)
      raise "Question '#{attributes[:question]}' already exists for #{attributes[:for_class]}. " \
            "Include its Id to update it instead."
    end

    # owner is forced to the entity rather than taken from the upload: WithDocQuestions
    # looks questions up with `entity.doc_questions.where(owner: entity, ...)`, so a
    # question owned by anything else imports cleanly and is then never asked.
    DocQuestion.create!(attributes.merge(entity_id: import_upload.entity_id,
                                         owner: import_upload.entity,
                                         import_upload_id: import_upload.id))
  end

  # A question is identified by what it asks, what it asks it of, and which documents
  # it applies to - the same columns a user would eyeball on the index page.
  def duplicate?(import_upload, attributes)
    DocQuestion.exists?(entity_id: import_upload.entity_id,
                        question: attributes[:question],
                        for_class: attributes[:for_class],
                        document_name: attributes[:document_name],
                        tags: attributes[:tags])
  end

  # The form and the download both round-trip the enum key ("validation"), while a
  # hand-typed sheet is far more likely to hold the label ("Validation"). Accept either,
  # in any case, and name the valid set when it is neither - the model's own inclusion
  # error only says "qtype is not included in the list".
  def parse_qtype(value)
    key = DocQuestion.qtypes.keys.find { |k| k.casecmp?(value.to_s.strip) }
    key ||= DocQuestion.qtypes.find { |_k, v| v.casecmp?(value.to_s.strip) }&.first
    raise "Type '#{value}' is not valid. Use one of: #{DocQuestion.qtypes.values.join(', ')}" if key.blank?

    key
  end

  def parse_for_class(value)
    for_class = DocQuestion::FOR_CLASSES.find { |c| c.casecmp?(value.to_s.strip) }
    raise "For '#{value}' is not valid. Use one of: #{DocQuestion::FOR_CLASSES.join(', ')}" if for_class.blank?

    for_class
  end
end
