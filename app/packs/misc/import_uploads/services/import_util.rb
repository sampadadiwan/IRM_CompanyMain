class ImportUtil
  include Interactor
  # Just stores the last model saved in the import. @see FormType.extract_from_db
  attr_accessor :last_saved

  def call
    if context.import_upload.present? && context.import_file.present?
      begin
        process_rows(context.import_upload, context.headers, context.data)
      rescue StandardError => e
        puts "e.message = #{e.message}"
        Rails.logger.debug e.backtrace
        raise e
      end
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def process_rows(import_upload, headers, data)
    Rails.logger.debug { "##### process_rows #{data.count}" }
    custom_field_headers = headers - standard_headers

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

    # Sometimes we import custom fields. Ensure custom fields get created
    FormType.extract_from_db(@last_saved) if @last_saved
    # Save the results file
    File.open("/tmp/import_result_#{import_upload.id}.xlsx", "wb") do |file|
      file.write(package.to_stream.read)
    end

    post_process(import_upload)
  end

  def post_process(import_upload); end

  def setup_custom_fields(user_data, model, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      model.properties ||= {}
      custom_field_headers.each do |cfh|
        Rails.logger.debug { "### setup_custom_fields: processing #{cfh}" }
        model.properties[cfh.parameterize.underscore] = user_data[cfh] if cfh.present?
      end
    end

    @last_saved = model
  end
end
