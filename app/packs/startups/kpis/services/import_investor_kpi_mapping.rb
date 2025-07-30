class ImportInvestorKpiMapping < ImportUtil
  # Defines the standard headers expected in the import file.
  STANDARD_HEADERS = [
    "Investor", "Reported Kpi Name", "Standard Kpi Name", "Category",
    "Data Type", "Parent Standard Kpi Name", "Position", "Show In Report",
    "Lower Threshold", "Upper Threshold"
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

    # Initialize or find an existing InvestorKpiMapping record.
    investor_kpi_mapping = initialize_investor_kpi_mapping(user_data, import_upload, investor)

    # Check if the row is marked for update only.
    update_only = user_data["Update Only"].to_s.downcase == "yes"
    if update_only
      if investor_kpi_mapping.persisted?
        Rails.logger.debug { "Updating existing investor_kpi_mapping with ID: #{investor_kpi_mapping.id}" }
        # If the mapping exists, update its attributes.
        save_investor_kpi_mapping(user_data, investor_kpi_mapping, custom_field_headers, import_upload, investor)
      else
        # Raise an error if the mapping does not exist for update.
        raise "InvestorKpiMapping not found for update with Standard Kpi Name '#{user_data['Standard Kpi Name']}' and Investor '#{user_data['Investor']}'"
      end
    elsif investor_kpi_mapping.persisted?
      Rails.logger.debug { "InvestorKpiMapping already exists with ID: #{investor_kpi_mapping.id}" }
      raise "InvestorKpiMapping already exists with Standard Kpi Name '#{user_data['Standard Kpi Name']}', Reported Kpi Name '#{user_data['Reported Kpi Name']}' and Investor '#{user_data['Investor']}'"
    else
      save_investor_kpi_mapping(user_data, investor_kpi_mapping, custom_field_headers, import_upload, investor)
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
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor with name '#{user_data['Investor']}' not found for entity #{import_upload.entity.name}" unless investor

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

    InvestorKpiMapping.find_or_initialize_by(
      entity: import_upload.entity,
      investor: investor,
      standard_kpi_name: user_data["Standard Kpi Name"],
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
    attributes = {
      category: user_data["Category"].presence,
      data_type: data_type,
      show_in_report: user_data["Show In Report"].to_s.downcase == "yes",
      lower_threshold: user_data["Lower Threshold"].presence,
      upper_threshold: user_data["Upper Threshold"].presence,
      position: user_data["Position"].presence,
      import_upload_id: import_upload.id
    }

    # Handle parent KPI mapping if provided.
    if user_data["Parent Standard Kpi Name"].present?
      parent_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: user_data["Parent Standard Kpi Name"],
                                                      entity: import_upload.entity, investor: investor)
      raise "Parent KPI Mapping with standard name '#{user_data['Parent Standard Kpi Name']}' for investor '#{investor}' not found" unless parent_kpi_mapping

      attributes[:parent_id] = parent_kpi_mapping.id
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
