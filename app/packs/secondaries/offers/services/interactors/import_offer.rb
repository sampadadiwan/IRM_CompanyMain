# TODO: Fix to really import offers
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
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def find_user; end

  def save_offer(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing offer #{user_data}" }

    # Get the holding for which the offer is being made
    # Get the Secondary Sale
    # Make the offer

    holding = Holding.new(user:, investor:, holding_type: user_data["Founder or Employee"],
                          entity_id: import_upload.owner_id, orig_grant_quantity: user_data["Quantity"],
                          price_cents:, employee_id: user_data["Employee ID"], department: user_data["Department"],
                          investment_instrument: user_data["Instrument"], funding_round: fr, option_pool: ep,
                          import_upload_id: import_upload.id, grant_date:, approved: false,
                          option_type: user_data["Option Type"], preferred_conversion: user_data["Preferred Conversion"])

    setup_custom_fields(user_data, holding, custom_field_headers)

    CreateHolding.call(holding:).holding
  end

  def setup_custom_fields(user_data, holding, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      holding.properties ||= {}
      custom_field_headers.each do |cfh|
        holding.properties[cfh.underscore] = user_data[cfh]
      end
    end
  end
end
