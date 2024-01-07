class ImportInvestorAccess < ImportUtil
  STANDARD_HEADERS = ["Investor", "First Name", "Last Name", "Email", "Cc", "Country Code", "Phone", "WhatsApp Enabled", "Approved", "Send Confirmation Email"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(params)
    super(params)
    @investor_accesses = []
  end

  def process_row(headers, _custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    begin
      status, msg = save_investor_access(user_data, import_upload)
      if status
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end
      row << msg
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      Rails.logger.debug { "Error #{e.message}" }
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_investor_access(user_data, import_upload)
    # next if user exists

    if user_data['Investor'].present?
      investor = import_upload.entity.investors.find_by(investor_name: user_data['Investor'])
      raise "Investor not found" unless investor
    else
      raise "Investor name is missing"
    end

    Rails.logger.debug user_data
    approved = user_data["Approved"] ? user_data["Approved"] == "Yes" : false
    whatsapp_enabled = user_data["WhatsApp Enabled"] ? user_data["WhatsApp Enabled"] == "Yes" : false
    call_code = user_data["Country Code"].present? ? extract_call_code(user_data["Country Code"].to_s) : "91"

    ia = InvestorAccess.new(first_name: user_data["First Name"], last_name: user_data["Last Name"], call_code:,
                            email: user_data["Email"], phone: user_data["Phone"].to_s,
                            approved:, whatsapp_enabled:, cc: user_data["Cc"],
                            entity_id: import_upload.entity_id, investor_id: investor.id,
                            granted_by: import_upload.user_id, import_upload_id: import_upload.id,
                            send_confirmation: user_data["Send Confirmation Email"] == "Yes")

    Rails.logger.debug { "Saving InvestorAccess with email '#{ia.email}'" }
    ia.save!
  end

  # accepts inputs - IN, in, in(+91), UaE(971), Us 1, etc
  def extract_call_code(input)
    # Convert the input to lowercase for consistent processing
    normalized_input = input.to_s.downcase
    # Regular expression pattern to match numeric call codes
    call_code_pattern = /\d+/

    # Search for numeric call code using the pattern
    match = normalized_input.match(call_code_pattern)

    # Check if a match was found and return the call code
    if match
      match[0]
    else
      # Try to extract from within round brackets
      bracket_pattern = /\((\d+)\)/
      bracket_match = normalized_input.match(bracket_pattern)
      if bracket_match
        bracket_match[0]
      else
        # Return the call code if country is found in the hash
        call_code = User::CALL_CODES[normalized_input]
        call_code.presence || raise(StandardError, "Invalid Country Code #{input}")
      end
    end
  end
end
