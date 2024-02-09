class ImportUtil
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      begin
        process_rows(context.import_upload, context.headers, context.data, context)
      rescue StandardError => e
        Rails.logger.debug { "e.message = #{e.message}" }
        Rails.logger.debug e.backtrace
        raise e
      end
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def validate_headers(headers)
    if respond_to?(:standard_headers)
      standard_headers.each do |header_name|
        raise "Column not found #{header_name}" unless headers.include?(header_name.downcase.strip.squeeze(" ").titleize)
      end
    end
  end

  def pre_process(import_upload, context); end

  def process_rows(import_upload, headers, data, context)
    Rails.logger.debug { "##### process_rows #{data.count}" }
    custom_field_headers = headers - standard_headers

    validate_headers(headers)

    pre_process(import_upload, context)

    # Parse the XL rows
    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        data.each_with_index do |row, idx|
          # skip header row
          if idx.zero?
            sheet.add_row(headers)
            next
          end

          # This sanitizes each row by stripping and squeezing spaces
          sanitized_row = row.map { |x| x&.to_s&.strip&.squeeze(" ") }
          # Ensure the Audit trail is created as the user who uploaded the file
          Audited.audit_class.as_user(import_upload.user) do
            process_row(headers, custom_field_headers, sanitized_row, import_upload, context)
          end
          # add row to results sheet
          sheet.add_row(sanitized_row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    # Sometimes we import custom fields. Ensure custom fields get created
    FormType.save_cf_from_import(custom_field_headers, import_upload) if import_upload.processed_row_count.positive?
    # Save the results file
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)

    post_process(import_upload, context)
  end

  def post_process(import_upload, context); end

  def setup_custom_fields(user_data, model, custom_field_headers)
    custom_field_headers -= ["Update Only"]
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      model.properties ||= {}
      custom_field_headers.each do |cfh|
        Rails.logger.debug { "### setup_custom_fields: processing #{cfh}" }
        model.properties[cfh.parameterize.underscore] = user_data[cfh] if cfh.present? # && user_data[cfh].present?
      end
    end
  end

  def setup_exchange_rate(model, user_data)
    ExchangeRate.create(from: user_data["From Currency"], to: user_data["To Currency"], as_of: user_data["As Of"], rate: user_data["Exchange Rate"], entity_id: model.entity_id, notes: "Imported with #{model}")
  end

  # get header row without the mandatory *
  def get_headers(headers)
    headers.filter(&:present?).each { |x| x.delete!("*") }.each(&:strip!)
  end

  def get_exchange_rates(file, _import_upload)
    exchange_rates = []
    # open spreadsheet with the rates sheet
    data = Roo::Spreadsheet.open(file.path).sheet("Exchange Rates")
    headers = get_headers(data.row(1))
    Rails.logger.debug { "## exchange rate headers = #{headers}" }

    data.each_with_index do |row, idx|
      # skip header row
      next if idx.zero?

      exchange_rate = [headers, row].transpose.to_h
      exchange_rate["As Of"] = Date.parse(exchange_rate["As Of"].to_s)
      exchange_rates << exchange_rate
    end

    # Sort by the as_of date
    exchange_rates.sort_by { |er| er["As Of"] }
  end

  def stz(val)
    val&.strip&.squeeze(" ")
  end
end
