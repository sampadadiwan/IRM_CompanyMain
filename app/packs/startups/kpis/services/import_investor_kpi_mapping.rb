class ImportInvestorKpiMapping < ImportUtil
  # Standard headers expected in the mapping bulk import CSV/Excel file.
  # "FX Conversion" added for KPI currency conversion — tells the parser which
  # FX rate method to apply per mapping (Not Applicable / Report Date / Average Rate).
  STANDARD_HEADERS = [
    "Stakeholder", "Reported Kpi Name", "Standard Kpi Name", "Category",
    "Data Type", "Denomination", "Fx Conversion", "Parent Standard Kpi Name", "Position",
    "Show In Report", "Lower Threshold", "Upper Threshold", "Auto Fill", "Compute Formula",
    "Update Only"
  ].freeze

  # Returns the standard headers for the import file.
  def standard_headers
    STANDARD_HEADERS
  end

  # Saves a row of user data to create or update an InvestorKpiMapping record.
  #
  # @param user_data [Hash] The data from the current row of the import file.
  # @param import_upload [ImportUpload] The current import upload object.
  # @param custom_field_headers [Array] Headers identified as custom fields.
  # @param _ctx [Hash] Context object (unused in this method).
  # @return [Boolean] True if the row was successfully saved.
  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing investor_kpi_mapping #{user_data}" }

    # Find the investor associated with the row data.
    investor = find_investor(user_data, import_upload)

    # Check if the row is marked for update only.
    update_only = user_data["Update Only"].to_s.downcase == "yes"

    if update_only
      id = user_data["Id"]
      if id.present?
        investor_kpi_mapping = InvestorKpiMapping.find_by(id: id, entity: import_upload.entity)
        raise "InvestorKpiMapping with id #{id} not found" unless investor_kpi_mapping
      else
        # Fallback to finding by names if ID is not provided but Update Only is "yes"
        investor_kpi_mapping = initialize_investor_kpi_mapping(user_data, import_upload, investor)
        raise "InvestorKpiMapping not found for update with Standard Kpi Name '#{user_data['Standard Kpi Name']}' and Investor '#{user_data['Stakeholder']}'" unless investor_kpi_mapping.persisted?
      end

      Rails.logger.debug { "Updating existing investor_kpi_mapping with ID: #{investor_kpi_mapping.id}" }
      save_investor_kpi_mapping(user_data, investor_kpi_mapping, custom_field_headers, import_upload, investor)
    else
      # Initialize or find an existing InvestorKpiMapping record.
      investor_kpi_mapping = initialize_investor_kpi_mapping(user_data, import_upload, investor)

      if investor_kpi_mapping.persisted?
        Rails.logger.debug { "InvestorKpiMapping already exists with ID: #{investor_kpi_mapping.id}" }
        raise "InvestorKpiMapping already exists with Standard Kpi Name '#{user_data['Standard Kpi Name']}', Reported Kpi Name '#{user_data['Reported Kpi Name']}' and Investor '#{user_data['Stakeholder']}'"
      else
        save_investor_kpi_mapping(user_data, investor_kpi_mapping, custom_field_headers, import_upload, investor)
      end
    end
    # Save the InvestorKpiMapping record and handle any errors.
  end

  private

  # Finds the investor associated with the given row data.
  #
  # @param user_data [Hash] The data from the current row of the import file.
  # @param import_upload [ImportUpload] The current import upload object.
  # @return [Investor] The investor object.
  # @raise [RuntimeError] If the investor is not found.
  def find_investor(user_data, import_upload)
    investor = import_upload.entity.investors.where(investor_name: user_data["Stakeholder"]).first
    raise "Investor with name '#{user_data['Stakeholder']}' not found for entity #{import_upload.entity.name}" unless investor

    investor
  end

  # Initializes or finds an existing InvestorKpiMapping record.
  #
  # @param user_data [Hash] The data from the current row of the import file.
  # @param import_upload [ImportUpload] The current import upload object.
  # @param investor [Investor] The investor object.
  # @return [InvestorKpiMapping] The initialized or existing InvestorKpiMapping record.
  # @raise [RuntimeError] If required fields are missing.
  def initialize_investor_kpi_mapping(user_data, import_upload, investor)
    raise "Standard Kpi Name is required" if user_data["Standard Kpi Name"].blank?
    raise "Reported Kpi Name is required" if user_data["Reported Kpi Name"].blank?

    standard_name = user_data["Standard Kpi Name"]

    # When a parent is specified, search by the prefixed name first
    # (e.g., "Net Sales - Enterprise") since set_investor_kpi_mapping_attributes
    # auto-prefixes on first import. Without this, re-imports search for
    # "Enterprise" but the DB has "Net Sales - Enterprise" — causing duplicates.
    if user_data["Parent Standard Kpi Name"].present?
      prefixed_name = "#{user_data['Parent Standard Kpi Name']} - #{standard_name}"
      existing = InvestorKpiMapping.find_by(
        entity: import_upload.entity,
        investor: investor,
        standard_kpi_name: prefixed_name,
        reported_kpi_name: user_data["Reported Kpi Name"]
      )
      return existing if existing
    end

    InvestorKpiMapping.find_or_initialize_by(
      entity: import_upload.entity,
      investor: investor,
      standard_kpi_name: standard_name,
      reported_kpi_name: user_data["Reported Kpi Name"]
    )
  end

  # Sets attributes for the InvestorKpiMapping record.
  #
  # @param user_data [Hash] The data from the current row of the import file.
  # @param investor_kpi_mapping [InvestorKpiMapping] The InvestorKpiMapping record.
  # @param import_upload [ImportUpload] The current import upload object.
  # @param investor [Investor] The investor object.
  # @raise [RuntimeError] If the parent KPI mapping is not found.
  def set_investor_kpi_mapping_attributes(user_data, investor_kpi_mapping, import_upload, investor)
    data_type = user_data["Data Type"].present? ? user_data["Data Type"].downcase : "numeric"

    autofill = user_data["Auto Fill"].present? ? user_data["Auto Fill"].to_s.downcase.strip.tr(" ", "_") : nil
    autofill = nil if autofill == "na"
    raise "Invalid autofill value '#{autofill}' for InvestorKpiMapping" if autofill.present? && InvestorKpiMapping.autofills.keys.exclude?(autofill)

    # Parse FX conversion method from import. Accepts "Not Applicable", "Report Date", "Average Rate".
    # Blank/missing defaults to "not_applicable" for backward compatibility — existing CSVs without
    # this column will work unchanged, and portcos reporting in the same currency as the fund skip conversion.
    fx_conversion = user_data["FX Conversion"].to_s.downcase.strip.tr(" ", "_")
    fx_conversion = "not_applicable" if fx_conversion.blank? || fx_conversion == "na"
    raise "Invalid FX Conversion value '#{user_data['FX Conversion']}' for InvestorKpiMapping" if InvestorKpiMapping.fx_conversion_methods.keys.exclude?(fx_conversion)

    attributes = {
      category: user_data["Category"].presence,
      data_type: data_type,
      denomination: user_data["Denomination"].presence,
      # FX conversion method determines how KPI values are converted from portco's reporting
      # currency to the fund's base currency during upload (not_applicable / report_date / average_rate).
      fx_conversion_method: fx_conversion,
      show_in_report: user_data["Show In Report"].to_s.downcase == "yes",
      lower_threshold: user_data["Lower Threshold"].presence,
      upper_threshold: user_data["Upper Threshold"].presence,
      position: user_data["Position"].presence,
      autofill: autofill,
      compute_formula: user_data["Compute Formula"].presence,
      import_upload_id: import_upload.id
    }

    # Handle parent KPI mapping if provided.
    # When a parent is set, the standard_kpi_name is automatically prefixed as
    # "Parent - Child" (e.g., "Net Sales - Enterprise") to ensure uniqueness.
    # This handles cases where the same child name (e.g., "Enterprise") appears
    # under multiple parents (e.g., Net Sales and Operating Cost). The FM only
    # needs to type the child name in the Standard Kpi Name column — the prefix
    # is added automatically. The reported_kpi_name stays as the raw child name
    # for matching against Excel cells during upload parsing.
    if user_data["Parent Standard Kpi Name"].present?
      parent_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: user_data["Parent Standard Kpi Name"],
                                                      entity: import_upload.entity, investor: investor)
      raise "Parent KPI Mapping with standard name '#{user_data['Parent Standard Kpi Name']}' for investor '#{investor}' not found" unless parent_kpi_mapping

      attributes[:parent_id] = parent_kpi_mapping.id

      # Auto-prefix standard_kpi_name with parent name for uniqueness.
      # Only prefix if not already prefixed (idempotent for re-imports).
      parent_prefix = "#{user_data['Parent Standard Kpi Name']} - "
      current_std_name = investor_kpi_mapping.standard_kpi_name
      unless current_std_name&.start_with?(parent_prefix)
        investor_kpi_mapping.standard_kpi_name = "#{parent_prefix}#{current_std_name}"
      end
    else
      attributes[:parent_id] = nil
    end

    investor_kpi_mapping.assign_attributes(attributes)
  end

  # Saves the InvestorKpiMapping record to the database.
  #
  # @param user_data [Hash] The data from the current row of the import file.
  # @param investor_kpi_mapping [InvestorKpiMapping] The InvestorKpiMapping record.
  # @return [Boolean] True if the record was successfully saved.
  def save_investor_kpi_mapping(user_data, investor_kpi_mapping, custom_field_headers, import_upload, investor)
    # Set attributes for the InvestorKpiMapping record.
    set_investor_kpi_mapping_attributes(user_data, investor_kpi_mapping, import_upload, investor)

    # Setup custom fields for the InvestorKpiMapping record.
    setup_custom_fields(user_data, investor_kpi_mapping, custom_field_headers - STANDARD_HEADERS)

    investor_kpi_mapping.save!

    Rails.logger.debug { "Successfully saved investor_kpi_mapping with ID: #{investor_kpi_mapping.id}" }
    true
  end
end
