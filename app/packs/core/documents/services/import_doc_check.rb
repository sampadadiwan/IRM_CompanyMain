# frozen_string_literal: true

# Imports Document Checks — what the AI reads from each KYC document (Fill in a field, Compare with a field,
# or a yes-no Question).
#
# The columns are the setup page's Export (views/doc_checks/index.xlsx.axlsx), so an exported sheet can be
# edited and uploaded back. The export's "Id" is what makes that round trip work: a row carrying one updates
# the check it came from; a row without one creates a check, and refuses one that already exists. Nothing is
# deleted — checks left out of the file stay as they are.
# Each row goes through DocCheck's own validation (as a save on the setup page), plus: the document must be
# on the entity's KYC document list (the setup page only offers those).
# See openspec/changes/document-checks/design.md (card ① Setup — Export and import).
# Worked examples H14, H15, E24, E25, X11, X12 — openspec/changes/document-checks/design.md#worked-examples
class ImportDocCheck < ImportUtil
  # DocCheck has no custom fields, so drop the step that would create them
  step nil, delete: :create_custom_fields

  # As the export writes them; ImportServiceBase titleizes headers, so they are read back as COLUMNS' values
  STANDARD_HEADERS = ["Document", "What To Do", "Look For", "KYC Field", "Tip", "Replace Existing", "Expected Answer"].freeze
  COLUMNS = STANDARD_HEADERS.index_with { |h| h.downcase.titleize }.freeze

  # The setup page's names for the three kinds of check, as the export writes them
  ACTIONS = { "Fill in" => "fill_in", "Compare" => "compare", "Question" => "question" }.freeze

  # DocCheck attribute → the column a row error names
  ERROR_COLUMNS = { field_name: "KYC Field", look_for: "Look For", tip: "Tip", action: "What To Do",
                    expected_answer: "Expected Answer", document_name: "Document" }.freeze

  RECORD_TYPE = "InvestorKyc"

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    entity = import_upload.entity
    # Read the row: the document as the entity's list spells it, the kind of check, and its field
    document_name = parse_document(entity, cell(user_data, COLUMNS["Document"], required: true))
    action = parse_action(cell(user_data, COLUMNS["What To Do"], required: true))
    attributes = {
      document_name:, action:,
      look_for: cell(user_data, COLUMNS["Look For"]).to_s,
      field_name: action == "question" ? nil : parse_field(entity, cell(user_data, COLUMNS["KYC Field"])),
      tip: cell(user_data, COLUMNS["Tip"]).to_s,
      replace_existing: flag?(cell(user_data, COLUMNS["Replace Existing"])),
      expected_answer: parse_answer(cell(user_data, COLUMNS["Expected Answer"]))
    }

    # An Id updates that check; no Id creates one
    id = cell(user_data, "Id").presence
    id.present? ? update_check(import_upload, id, attributes) : create_check(import_upload, attributes)
    true
  end

  private

  def update_check(import_upload, id, attributes)
    check = DocCheck.where(entity_id: import_upload.entity_id, record_type: RECORD_TYPE, id:).first
    raise "No check found with Id #{id}. Leave Id blank to create a new check." if check.nil?

    # import_upload_id is left alone: Delete Imported Data destroys what an upload created, so an upload
    # that only edited a check must not take it over
    check.assign_attributes(attributes)
    save!(check)
  end

  def create_check(import_upload, attributes)
    check = DocCheck.new(attributes.merge(entity_id: import_upload.entity_id, record_type: RECORD_TYPE,
                                          import_upload_id: import_upload.id, position: next_position(import_upload, attributes)))
    save!(check)
  end

  # Model validation errors, named by their column — "KYC Field: Already used on this document"; a check that
  # is already there says how to update it instead
  def save!(check)
    return check.save! if check.valid?

    duplicate = check.errors.any? { |e| e.message.start_with?("Already") }
    messages = check.errors.map { |e| "#{ERROR_COLUMNS.fetch(e.attribute, e.attribute.to_s.humanize)}: #{e.message}" }
    messages << "Include its Id to update it instead" if duplicate && check.new_record?
    raise messages.join(". ")
  end

  # New checks go after the document's existing ones
  def next_position(import_upload, attributes)
    DocCheck.where(entity_id: import_upload.entity_id, record_type: RECORD_TYPE)
            .where("LOWER(document_name) = ?", attributes[:document_name].downcase).maximum(:position).to_i + 1
  end

  # The entity's KYC document list, matched ignoring case. Worked example E25.
  def parse_document(entity, value)
    names = DocChecks::Registry.for(RECORD_TYPE).document_names(entity)
    name = names.find { |n| n.casecmp?(value.to_s.squish) }
    raise "Document '#{value}' is not on your KYC document list. Use one of: #{names.join(', ')}" if name.nil?

    name
  end

  def parse_action(value)
    action = ACTIONS.find { |label, key| label.casecmp?(value.to_s.squish) || key.casecmp?(value.to_s.squish) }&.last
    raise "What To Do '#{value}' is not valid. Use one of: #{ACTIONS.keys.join(', ')}" if action.nil?

    action
  end

  # The label users see ("Full name") or the field's name ("full_name"); a label two fields share must be
  # given by name. Worked example X12.
  def parse_field(entity, value)
    raise "KYC Field must be specified for Fill in and Compare" if value.to_s.strip.blank?

    fields = DocChecks::Registry.for(RECORD_TYPE).fields_for(entity)
    wanted = value.to_s.squish
    by_name = fields.find { |f| f.name == wanted } || fields.find { |f| f.name.casecmp?(wanted) }
    return by_name.name if by_name

    by_label = fields.select { |f| f.label.to_s.casecmp?(wanted) }
    raise "KYC Field '#{value}' matches #{by_label.map(&:name).join(' and ')} — use the field's name" if by_label.size > 1
    raise "KYC Field '#{value}' is not on your KYC form" if by_label.empty?

    by_label.first.name
  end

  # Yes/No, blank meaning Yes (only a Question uses it)
  def parse_answer(value)
    return "yes" if value.to_s.strip.blank?

    answer = DocCheck::ANSWERS.find { |a| a.casecmp?(value.to_s.strip) }
    raise "Expected Answer '#{value}' is not valid. Use Yes or No" if answer.nil?

    answer
  end
end
