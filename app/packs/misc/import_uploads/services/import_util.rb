class ImportUtil < Trailblazer::Operation
  step :validate_headers
  step :pre_process
  step :save_data
  step :create_custom_fields
  step :post_process
  left :cleanup

  def save_data(ctx, import_upload:, import_file:, headers:, data:, **)
    if defer_counter_culture_updates
      # In some cases we dont want the counter caches to run during the import
      # As this causes deadlocks. We will update the counter caches after the import
      model_class = import_upload.model_class
      model_class.skip_counter_culture_updates do
        process_rows(import_upload, headers, data, ctx)
      end
    else
      process_rows(import_upload, headers, data, ctx)
    end
  rescue StandardError => e
    Rails.logger.debug { "e.message = #{e.message}" }
    Rails.logger.debug e.backtrace
    raise e
  end

  def validate_headers(_ctx, import_upload:, headers:, **)
    valid = true
    if respond_to?(:standard_headers)
      standard_headers.each do |header_name|
        next if headers.include?(header_name.downcase.strip.squeeze(" ").titleize)

        import_upload.status = "Column not found #{header_name}"
        import_upload.failed_row_count = import_upload.total_rows_count
        import_upload.save
        valid = false
        break
      end
    end
    valid
  end

  def pre_process(_ctx, import_upload:, **)
    true
  end

  def create_custom_fields(_ctx, import_upload:, custom_field_headers:, **)
    # Sometimes we import custom fields. Ensure custom fields get created
    result = true
    if import_upload.processed_row_count.positive?
      custom_fields_created = FormType.save_cf_from_import(custom_field_headers, import_upload)
      if custom_fields_created.present?
        import_upload.custom_fields_created = custom_fields_created.join(";")
        result = import_upload.save
      end
    end
    result
  end

  def post_process(_ctx, import_upload:, **)
    # Update the counter caches
    if defer_counter_culture_updates
      model_class = import_upload.model_class
      model_class.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }
    end
    # The custom fields have been created. Now we can update the form_type for newly created records
    import_upload.form_type_names.each do |form_type_name|
      form_type = import_upload.entity.form_types.where(name: form_type_name).last
      form_type_name.constantize.update_all(entity_id: import_upload.entity_id, import_upload_id: import_upload.id, form_type_id: form_type.id) if form_type.present?
    end

    true
  end

  def cleanup(_ctx, import_upload:, **)
    false
  end

  # get header row without the mandatory *
  def get_headers(headers)
    # The headers are transformed by strip, squeeze and titleize and then stripped of *
    ret_headers = headers.each { |x| x&.delete!("*") }.map { |h| h&.downcase&.strip&.squeeze(" ")&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end

  private

  def process_rows(import_upload, headers, data, ctx)
    Rails.logger.debug { "##### process_rows #{data.count}" }
    custom_field_headers = headers - standard_headers
    ctx[:custom_field_headers] = custom_field_headers

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
            process_row(headers, custom_field_headers, sanitized_row, import_upload, ctx)
          end
          # add row to results sheet
          sheet.add_row(sanitized_row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    # Save the results file
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
  end

  def process_row(headers, custom_field_headers, row, import_upload, _ctx)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_row(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end

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

  def defer_counter_culture_updates
    false
  end
end
