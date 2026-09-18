# frozen_string_literal: true

# Service for importing FundFormulas for a given Fund.
# The import file can contain new formulas to be created or existing formulas to be updated.
class ImportFundFormula < ImportUtil
  # FundFormula does not have a custom_field model, so we skip the step that would try to create them.
  step nil, delete: :create_custom_fields

  # Defines the standard headers expected in the import file.
  STANDARD_HEADERS = ["Sequence", "Name", "Description", "Rule Type", "Rule For", "Formula", "Entry Type", "Rollup", "Enabled", "Tag List", "Generate Ytd, Quarterly, Since Inception Numbers", "Metadata", "Cache"].freeze

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
    # The fund is the upload owner, not a column in the sheet
    raise "Fund not found - upload fund formulas against a fund" unless fund

    attrs = FundFormulaAttributes.from_row(row_data)
    sequence = attrs.delete(:sequence)
    update_only = row_data["Update Only"]&.downcase == "yes"

    if update_only
      id = row_data["Id"]
      raise "FundFormula Id must be present for update only" unless id

      fund_formula = fund.fund_formulas.find_by(id:)
      raise "FundFormula with id #{id} not found for Fund #{fund.id}" unless fund_formula

      attrs[:sequence] = sequence.to_i if sequence
      fund_formula.update!(**attrs, import_upload_id: import_upload.id)

    else
      # Find by a composite key of attributes to prevent duplicates.
      fund_formula = fund.fund_formulas.find_or_initialize_by(entity_id: fund.entity_id, **attrs.slice(:name, :description, :rule_type, :rule_for, :formula, :entry_type, :generate_ytd_qtly, :meta_data))

      raise "FundFormula #{fund_formula.id} already exists" if fund_formula.id.present?

      attrs[:sequence] = sequence.to_i if sequence
      fund.fund_formulas.create!(**attrs, entity_id: fund.entity_id, fund_id: fund.id, import_upload_id: import_upload.id)
    end

    true
  end
end
