class ImportCapitalRemittance < ImportUtil
  STANDARD_HEADERS = ["Fund", "Capital Call", "Call Amount (Inclusive Of Capital Fees, Folio Currency)", "Capital Fees (Folio Currency)", "Other Fees (Folio Currency)", "Call Amount (Inclusive Of Capital Fees, Fund Currency)", "Capital Fees (Fund Currency)", "Other Fees (Fund Currency)", "Investment Amount (Fund Currency)", "Remittance Date", "Verified", "Folio No"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  # Older templates may still carry a Stakeholder column - ignore it so it does not become a custom field
  def ignore_headers
    ["Stakeholder"]
  end

  # Method to save a row of user data
  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_remittance #{user_data}" }

    # Retrieve necessary inputs
    fund, capital_call, investor, folio_id, capital_commitment = inputs(import_upload, user_data)

    # Check if all required entities are present and valid
    if fund && capital_call && capital_commitment && investor

      # Create a new CapitalRemittance object
      capital_remittance = CapitalRemittance.new(
        # The entity object (loaded once per upload), not its id - the remittance's callbacks read it, and an
        # id alone made every row fetch the entity again
        entity: import_upload.entity,
        fund: fund,
        capital_call: capital_call,
        investor: investor,
        investor_name: investor.investor_name,
        capital_commitment: capital_commitment,
        folio_id: folio_id,
        import_upload_id: import_upload.id,
        payment_date: user_data["Payment Date"],
        created_by: "Upload",
        remittance_date: user_data["Remittance Date"],
        call_basis: "Upload"
      )

      setup_amounts(user_data, capital_remittance, fund)

      # Set the verified status based on user data
      capital_remittance.verified = user_data["Verified"] == "Yes"

      # Setup custom fields for the capital remittance
      setup_custom_fields(user_data, capital_remittance, custom_field_headers)

      # Attempt to create the capital remittance and handle any errors
      result = CapitalRemittanceCreate.call(capital_remittance: capital_remittance)
      raise result[:errors] unless result.success?

      result.success?
    else
      # Unreachable - inputs raises on each of these - but kept so a future edit
      # cannot fall through and leave the row with an unexplained "Error"
      raise "Fund not found: #{user_data['Fund']}" unless fund
      raise "Capital Call not found: #{user_data['Capital Call']}" unless capital_call
      raise "Capital Commitment not found for folio #{folio_id}" unless capital_commitment

      raise "Investor not found for folio #{folio_id}"
    end
  end

  def setup_amounts(user_data, capital_remittance, _fund)
    # Set the folio currency amounts based on user data
    capital_remittance.folio_call_amount = user_data["Call Amount (Inclusive Of Capital Fees, Folio Currency)"]
    capital_remittance.folio_capital_fee = user_data["Capital Fees (Folio Currency)"]
    capital_remittance.folio_other_fee = user_data["Other Fees (Folio Currency)"]

    # Sometimes we also get the amounts in fund currency
    capital_remittance.call_amount = user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"] if user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].present?
    capital_remittance.capital_fee = user_data["Capital Fees (Fund Currency)"] if user_data["Capital Fees (Fund Currency)"].present?
    capital_remittance.other_fee = user_data["Other Fees (Fund Currency)"] if user_data["Other Fees (Fund Currency)"].present?
    capital_remittance.investment_amount = user_data["Investment Amount (Fund Currency)"] if user_data["Investment Amount (Fund Currency)"].present?
  end

  # Method to retrieve necessary inputs from user data and import upload
  def inputs(import_upload, user_data)
    # Find the fund based on the name provided in user data - bail out with a
    # readable message rather than a NoMethodError on nil further down
    fund_name = user_data["Fund"]&.to_s&.strip
    raise "Fund must be specified" if fund_name.blank?

    fund = import_upload.entity.funds.where(name: fund_name).first
    raise "Fund not found: #{fund_name}" unless fund

    # Find the capital call associated with the fund based on the name provided in user data
    capital_call_name = user_data["Capital Call"]&.to_s&.strip
    raise "Capital Call must be specified" if capital_call_name.blank?

    capital_call = fund.capital_calls.where(name: capital_call_name).first
    raise "Capital Call not found for fund #{fund_name}: #{capital_call_name}" unless capital_call

    # Retrieve the folio ID from user data
    folio_id = user_data["Folio No"]&.to_s
    raise "Folio No must be specified" if folio_id.blank?

    # Find the capital commitment purely via the folio ID - the investor is derived from the commitment
    capital_commitment = fund.capital_commitments.where(folio_id:).first
    raise "Capital Commitment not found for fund #{fund_name}, folio #{folio_id}" unless capital_commitment

    investor = capital_commitment.investor
    raise "Investor not found for folio #{folio_id}" unless investor

    # Return the retrieved inputs as an array
    [fund, capital_call, investor, folio_id, capital_commitment]
  end

  def defer_counter_culture_updates
    true
  end
end
