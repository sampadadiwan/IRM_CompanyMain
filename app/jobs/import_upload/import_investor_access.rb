class ImportInvestorAccess
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      process_investor_access(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def save_investor_access(user_data, import_upload)
    # next if user exists
    if InvestorAccess.exists?(email: user_data['Email'], investor_id: import_upload.owner_id)
      Rails.logger.debug { "InvestorAccess with email #{user_data['Email']} already exists for investor #{import_upload.owner_id}" }
      return false
    end

    Rails.logger.debug user_data
    approved = user_data["Approved"] ? user_data["Approved"].strip == "Yes" : false
    ia = InvestorAccess.new(first_name: user_data["First Name"], last_name: user_data["Last Name"],
                            email: user_data["Email"], approved:,
                            entity_id: import_upload.entity_id, investor_id: import_upload.owner_id,
                            granted_by: import_upload.user_id)

    Rails.logger.debug { "Saving InvestorAccess with email '#{ia.email}'" }
    ia.save
  end

  def process_investor_access(_file, import_upload)
    headers = context.headers
    data = context.data
    # Parse the XL rows

    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      if save_investor_access(user_data, import_upload)
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end

      # To indicate progress
      import_upload.save if (idx % 10).zero?
    end
  end
end
