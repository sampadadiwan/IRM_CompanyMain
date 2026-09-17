# frozen_string_literal: true

# Service for importing RatioFormulas for a given Fund.
# The import file can contain new formulas to be created or existing formulas to be updated.
class ImportRatioFormula < ImportUtil
  # RatioFormula does not have a custom_field model, so skip that step.
  step nil, delete: :create_custom_fields

  # Columns expected in the import file (must match headers exactly, case-insensitive after titleize).
  STANDARD_HEADERS = ["Level", "Action", "Period", "Ratio", "Label", "Account Entry Names", "Entry Type", "Parent Type", "Cumulative", "Skip Portfolio Fmv"].freeze

  # Returns the standard headers so ImportUtil can validate the uploaded file.
  def standard_headers
    STANDARD_HEADERS
  end

  # Processes and saves a single row from the import file.
  # Supports both create (default) and update-only (when "Update Only" column == "yes").
  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug row_data

    fund = import_upload.owner
    # The fund is the upload owner, not a column in the sheet
    raise "Fund not found - upload ratio formulas against a fund" unless fund

    # Accept both humanized text ("Add cashflow", "As on") and raw enum values ("add_cashflow", "as_on").
    level               = lookup_enum(RatioFormula.level,  row_data["Level"])
    action              = lookup_enum(RatioFormula.action, row_data["Action"])
    period              = lookup_enum(RatioFormula.period, row_data["Period"])
    label               = row_data["Label"].to_s.strip
    ratio               = row_data["Ratio"].to_s.strip
    account_entry_names = split_csv(row_data["Account Entry Names"])
    entry_type          = row_data["Entry Type"].to_s.strip
    parent_type         = row_data["Parent Type"].to_s.strip
    cumulative          = row_data["Cumulative"].to_s.strip.downcase == "yes"
    skip_portfolio_fmv  = row_data["Skip Portfolio Fmv"].to_s.strip.downcase == "yes"
    update_only         = row_data["Update Only"].to_s.strip.downcase == "yes"

    if update_only
      id = row_data["Id"]
      raise "RatioFormula Id must be present for update only" unless id

      ratio_formula = fund.ratio_formulas.find_by(id:)
      raise "RatioFormula with id #{id} not found for Fund #{fund.id}" unless ratio_formula

      ratio_formula.update!(
        level:, action:, period:, ratio:, label:, account_entry_names:,
        entry_type:, parent_type:, cumulative:, skip_portfolio_fmv:,
        import_upload_id: import_upload.id
      )
    else
      label = nil if label.blank? # Normalize blank labels to nil for consistent deduplication
      # Deduplicate on the full composite key; raise if it already exists.
      ratio_formula = fund.ratio_formulas.find_or_initialize_by(
        entity_id: fund.entity_id,
        ratio:,
        entry_type:, parent_type:, cumulative:,
        level:, action:, period:,
        label:
      )

      raise "RatioFormula #{ratio_formula.id} already exists" if ratio_formula.id.present?

      fund.ratio_formulas.create!(
        entity_id: fund.entity_id,
        fund_id: fund.id,
        level:, action:, period:, ratio:, label:, account_entry_names:,
        entry_type:, parent_type:, cumulative:, skip_portfolio_fmv:,
        import_upload_id: import_upload.id
      )
    end

    true
  end

  private

  # Splits a comma-separated string into a trimmed array; used for account_entry_names.
  def split_csv(value)
    return [] if value.blank?

    value.to_s.split(",").map(&:strip).compact_blank
  end

  # Resolves a cell value to its enum key, accepting either the humanized text
  # ("Add cashflow") or the raw value ("add_cashflow").
  def lookup_enum(enum_set, cell_value)
    return nil if cell_value.blank?

    text = cell_value.to_s.strip
    # Try exact match on raw value first, then case-insensitive match on humanized text.
    match = enum_set.values.find { |v| v.value.to_s == text } ||
            enum_set.values.find { |v| v.text.to_s.casecmp?(text) }
    raise "Unknown value '#{text}' for #{enum_set.attribute_name}" unless match

    match.value
  end
end
