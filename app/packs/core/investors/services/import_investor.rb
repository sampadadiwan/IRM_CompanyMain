class ImportInvestor
  include Interactor

  STANDARD_HEADERS = %w[Name Category Tags City Fund].freeze

  def call
    if context.import_upload.present? && context.import_file.present?
      process_investor(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def save_investor(user_data, import_upload, custom_field_headers)
    # puts "processing #{user_data}"
    ia = Investor.where(investor_name: user_data['Name'], entity_id: import_upload.entity_id).first
    if ia.present?
      Rails.logger.debug { "Investor with name #{user_data['Name']} already exists for entity #{import_upload.entity_id}" }

    else

      Rails.logger.debug user_data
      ia = Investor.new(investor_name: user_data["Name"], tag_list: user_data["Tags"],
                        category: user_data["Category"], city: user_data["City"],
                        entity_id: import_upload.entity_id)

      setup_custom_fields(user_data, ia, custom_field_headers)

      Rails.logger.debug { "Saving Investor with name '#{ia.investor_name}'" }
      ia.save

    end

    # If fund name is present, add this investor to the fund
    if user_data["Fund"].present?
      # "puts ######## Fund present #{user_data["Fund"]}"
      fund = Fund.where(entity_id: import_upload.entity_id, name: user_data["Fund"].strip).first
      if fund
        # Give the investor access rights as an investor to the fund
        AccessRight.create!(entity_id: fund.entity_id, owner: fund, investor: ia, access_type: "Fund", metadata: "Investor")
      else
        Rails.logger.debug { "Specified fund #{user_data['Fund']} not found in import_upload #{import_upload.id}" }
      end
    end
  end

  def setup_custom_fields(user_data, model, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      model.properties ||= {}
      custom_field_headers.each do |cfh|
        model.properties[cfh.underscore] = user_data[cfh]
      end
    end
  end

  def process_investor(_file, import_upload)
    headers = context.headers
    custom_field_headers = headers - STANDARD_HEADERS

    data = context.data
    # Parse the XL rows

    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      if save_investor(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end

      # To indicate progress
      import_upload.save if (idx % 10).zero?
    end
  end
end
