class ImportUtil
  include Interactor
  # Just stores the last model saved in the import. @see FormType.extract_from_db
  attr_accessor :last_saved

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
        raise "Column not found #{header_name}" unless headers.include?(header_name)
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
          next if idx.zero?

          process_row(headers, custom_field_headers, row, import_upload, context)
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
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)

    post_process(import_upload, context)
  end

  def post_process(import_upload, context); end

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
