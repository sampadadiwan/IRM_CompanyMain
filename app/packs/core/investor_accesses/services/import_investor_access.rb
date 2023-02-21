class ImportInvestorAccess < ImportUtil
  STANDARD_HEADERS = ["Investor", "First Name", "Last Name", "Email", "Approved", "Send Confirmation"].freeze

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
      return false unless investor
    else
      investor = import_upload.owner
    end

    if InvestorAccess.exists?(email: user_data['Email'], investor_id: investor.id)
      Rails.logger.debug { "InvestorAccess with email #{user_data['Email']} already exists for investor #{investor.id}" }
      return false
    end

    Rails.logger.debug user_data
    approved = user_data["Approved"] ? user_data["Approved"].strip == "Yes" : false
    ia = InvestorAccess.new(first_name: user_data["First Name"], last_name: user_data["Last Name"],
                            email: user_data["Email"], approved:,
                            entity_id: import_upload.entity_id, investor_id: investor.id,
                            granted_by: import_upload.user_id,
                            send_confirmation: user_data["Send Confirmation Email"] == "Yes")

    Rails.logger.debug { "Saving InvestorAccess with email '#{ia.email}'" }
    ia.save
  end
end
