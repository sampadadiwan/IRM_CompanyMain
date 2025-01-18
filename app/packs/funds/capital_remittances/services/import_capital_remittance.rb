class ImportCapitalRemittance < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Call Amount (Inclusive Of Capital Fees)", "Capital Fees", "Other Fees", "Remittance Date", "Verified", "Folio No"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  # Method to save a row of user data
  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_remittance #{user_data}" }

    # Retrieve necessary inputs
    fund, capital_call, investor, folio_id, capital_commitment = inputs(import_upload, user_data)

    # Check if all required entities are present and valid
    if fund && capital_call && investor && capital_commitment && capital_commitment.investor_id == investor.id

      # Create a new CapitalRemittance object
      capital_remittance = CapitalRemittance.new(
        entity_id: import_upload.entity_id,
        fund: fund,
        capital_call: capital_call,
        investor: investor,
        investor_name: investor.investor_name,
        capital_commitment: capital_commitment,
        folio_id: folio_id,
        import_upload_id: import_upload.id,
        payment_date: user_data["Payment Date"],
        created_by: "Upload",
        remittance_date: user_data["Remittance Date"]
      )

      # Some funds are setup to user the folio amount as the basis for remittance generation. other the fund amount
      # Folio Amount: Use the folio_committed_amount_cents as the basis for remittance generation.
      # Fund Amount: Use the committed_amount_cents as the basis for remittance generation.    
      remittance_generation_basis = fund.remittance_generation_basis
      if fund.remittance_generation_basis == 'Folio Amount'
        capital_remittance.folio_call_amount = user_data["Call Amount (Inclusive Of Capital Fees)"]
        capital_remittance.folio_capital_fee = user_data["Capital Fees"]
        capital_remittance.folio_other_fee = user_data["Other Fees"]
      elsif fund.remittance_generation_basis == 'Fund Amount'
        capital_remittance.call_amount = user_data["Call Amount (Inclusive Of Capital Fees)"]
        capital_remittance.capital_fee = user_data["Capital Fees"]
        capital_remittance.other_fee = user_data["Other Fees"]
      else
        raise "Unknown Fund.remittance_generation_basis: #{remittance_generation_basis}"
      end

      # Set the verified status based on user data
      capital_remittance.verified = user_data["Verified"] == "Yes"

      # Setup custom fields for the capital remittance
      setup_custom_fields(user_data, capital_remittance, custom_field_headers)

      # Attempt to create the capital remittance and handle any errors
      result = CapitalRemittanceCreate.wtf?(capital_remittance: capital_remittance)
      raise result[:errors] unless result.success?

      result.success?
    else
      # Raise appropriate errors if any required entity is missing or invalid
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Investor not found" unless investor
      raise "Capital Commitment not found" unless capital_commitment
      raise "Investor and Commitment do not match" if capital_commitment.investor_id != investor.id
    end
  end

  # Method to retrieve necessary inputs from user data and import upload
  def inputs(import_upload, user_data)
    # Find the fund based on the name provided in user data
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first

    # Find the capital call associated with the fund based on the name provided in user data
    capital_call = fund.capital_calls.where(name: user_data["Capital Call"]).first

    # Find the investor based on the name provided in user data
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    # Retrieve the folio ID from user data
    folio_id = user_data["Folio No"]&.to_s

    # Find the capital commitment associated with the fund, investor, and folio ID
    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, folio_id:).first

    # Return the retrieved inputs as an array
    [fund, capital_call, investor, folio_id, capital_commitment]
  end

  def defer_counter_culture_updates
    true
  end
end
