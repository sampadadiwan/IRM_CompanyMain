class ImportOffer
  include Interactor
  STANDARD_HEADERS = ["User (email)", "Offer Quantity", "First Name", "Middle Name", "Last Name", "Address", "PAN", "Bank Account", "IFSC Code"].freeze
  def call
    if context.import_upload.present? && context.import_file.present?
      process_offers(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def process_offers(_file, import_upload)
    headers = context.headers
    custom_field_headers = headers - STANDARD_HEADERS

    data = context.data

    # Parse the XL rows
    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        data.each_with_index do |row, idx|
          # skip header row
          next if idx.zero?

          process_row(headers, custom_field_headers, row, import_upload)
          # add row to results sheet
          sheet.add_row(row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    File.write("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_offer(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def find_user; end

  def save_offer(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing offer #{user_data}" }

    # Get the holding for which the offer is being made
    holding = Holding.joins(:user).where("users.email=? and holdings.entity_id=?",
                                         user_data["Email"], import_upload.entity_id).first
    # Get the Secondary Sale
    secondary_sale = import_upload.entity.secondary_sales.last
    # Make the offer

    offer = Offer.new(PAN: user_data["PAN"], address: user_data["Address"], city: user_data["City"],
                      demat: user_data["Demat"], quantity: user_data["Quantity"], bank_account_number: user_data["Bank Account Number"], ifsc_code: user_data["IFSC Code"],
                      holding:, secondary_sale:, final_price: secondary_sale.final_price,
                      user: holding.user, investor: holding.investor, entity: holding.entity,
                      full_name: holding.user&.full_name)

    setup_custom_fields(user_data, offer, custom_field_headers)

    offer.save
  end

  def setup_custom_fields(user_data, offer, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      offer.properties ||= {}
      custom_field_headers.each do |cfh|
        offer.properties[cfh.underscore] = user_data[cfh]
      end
    end
  end

  def adhoc_update(file_path, secondary_sale_id)
    secondary_sale = SecondarySale.find(secondary_sale_id)

    data = Roo::Spreadsheet.open(file_path) # open spreadsheet
    headers = data.row(1) # get header row

    data.each_with_index do |row, idx|
      # skip header row
      next if idx.zero?

      user_data = [headers, row].transpose.to_h

      first_name, last_name = user_data["Seller name"].split
      u = User.joins(:offers).where('offers.entity_id': secondary_sale.entity_id,
                                    'users.first_name': first_name.strip,
                                    'users.last_name': last_name.strip).first

      if u
        secondary_sale.offers.where(user_id: u.id).update(
          bank_name: user_data["Bank Name"].strip,
          bank_account_number: user_data["Bank Account Number"].strip,
          ifsc_code: user_data["IFSC CODE"].strip
        )

      else
        Rails.logger.debug { "No user found for row #{idx} #{user_data} #{first_name} #{last_name}" }
      end
    end
  end
end
