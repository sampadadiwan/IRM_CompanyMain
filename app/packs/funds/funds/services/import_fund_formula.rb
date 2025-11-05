# frozen_string_literal: true

# Service for importing FundFormulas for a given Fund.
# The import file can contain new formulas to be created or existing formulas to be updated.
class ImportFundFormula < ImportUtil
  # FundFormula does not have a custom_field model, so we skip the step that would try to create them.
  step nil, delete: :create_custom_fields

  # Defines the standard headers expected in the import file.
  STANDARD_HEADERS = ["Sequence", "Name", "Description", "Rule Type", "Rule For", "Formula", "Entry Type", "Rollup", "Enabled", "Tag List", "Generate Ytd, Quarterly, Since Inception Numbers", "Metadata"].freeze

  # Returns the standard headers for the import file.
  # @return [Array<String>]
  def standard_headers
    STANDARD_HEADERS
  end

  # Processes and saves a single row from the import file.
  # This method handles both creating new FundFormulas and updating existing ones.
  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug row_data

    fund = import_upload.owner
    raise "Fund not found" unless fund

    name, description, entry_type, formula, rule_type, rule_for, tag_list, roll_up, meta_data, generate_ytd_qtly, enabled, sequence = read_row_data(row_data)
    update_only = row_data["Update Only"]&.downcase == "yes"

    if update_only
      id = row_data["Id"]
      raise "FundFormula Id must be present for update only" unless id

      fund_formula = fund.fund_formulas.find_by(id:)
      raise "FundFormula with id #{id} not found for Fund #{fund.id}" unless fund_formula

      attrs = { name:, description:, rule_type:, rule_for:, formula:, entry_type:, roll_up:, enabled:, tag_list:, generate_ytd_qtly:, meta_data:, import_upload_id: import_upload.id }
      attrs[:sequence] = sequence.presence&.to_i if sequence.present?
      fund_formula.update!(attrs)

    else
      # Find by a composite key of attributes to prevent duplicates.
      fund_formula = fund.fund_formulas.find_or_initialize_by(entity_id: fund.entity_id, name:, description:, rule_type:, rule_for:, formula:, entry_type:, generate_ytd_qtly:, meta_data:)

      if fund_formula.id.present?
        raise "FundFormula #{fund_formula.id} already exists"
      else
        attrs = { entity_id: fund.entity_id, fund_id: fund.id, name:, description:, rule_type:, rule_for:, formula:, entry_type:, roll_up:, enabled:, import_upload_id: import_upload.id, tag_list:, generate_ytd_qtly:, meta_data: }
        attrs[:sequence] = sequence.presence&.to_i if sequence.present?
        fund.fund_formulas.create!(attrs)
      end
    end

    true
  end

  # Reads and parses data from a row hash into individual variables.
  #
  # @param row_data [Hash] The data for a single row.
  # @return [Array] An array of parsed values from the row.
  def read_row_data(row_data)
    name = row_data["Name"]
    description = row_data["Description"]
    entry_type = row_data["Entry Type"]
    formula = row_data["Formula"]
    rule_type = row_data["Rule Type"]
    rule_for = row_data["Rule For"]
    tag_list = row_data["Tag List"]
    roll_up = row_data["Rollup"]&.downcase == "yes"
    meta_data = row_data["Metadata"]
    generate_ytd_qtly = row_data["Generate Ytd, Quarterly, Since Inception Numbers"]&.downcase == "yes"
    enabled = row_data["Enabled"]&.downcase == "yes"
    sequence = row_data["Sequence"]&.strip

    [name, description, entry_type, formula, rule_type, rule_for, tag_list, roll_up, meta_data, generate_ytd_qtly, enabled, sequence]
  end
end
