class ImportInvestor
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      process_investor(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def save_investor(user_data, import_upload)
    if Investor.exists?(investor_name: user_data['Name'], entity_id: import_upload.entity_id)
      Rails.logger.debug { "Investor with name #{user_data['Name']} already exists for entity #{import_upload.entity_id}" }
      return false
    end

    Rails.logger.debug user_data
    ia = Investor.new(investor_name: user_data["Name"], tag_list: user_data["Tags"],
                      category: user_data["Category"], city: user_data["City"],
                      entity_id: import_upload.entity_id)

    Rails.logger.debug { "Saving Investor with name '#{ia.investor_name}'" }
    ia.save
  end

  def process_investor(_file, import_upload)
    headers = context.headers
    data = context.data
    # Parse the XL rows

    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      if save_investor(user_data, import_upload)
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end

      # To indicate progress
      import_upload.save if (idx % 10).zero?
    end
  end
end
