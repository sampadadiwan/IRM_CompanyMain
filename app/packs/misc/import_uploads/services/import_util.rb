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
      # Check if all the standard headers are present
      standard_headers.each do |header_name|
        next if headers.include?(header_name.downcase.strip.squeeze(" ").titleize)

        import_upload.status = "Column not found #{header_name}"
        import_upload.failed_row_count = import_upload.total_rows_count
        import_upload.save
        valid = false
        break
      end
      # Check there are no duplicate column names
      if headers.uniq.length != headers.length
        valid = false
        # Get the duplicate column names
        dups = headers.select { |e| headers.count(e) > 1 }.uniq
        import_upload.status = "Duplicate columns found #{dups}"
        import_upload.failed_row_count = import_upload.total_rows_count
        import_upload.save
      end
    end
    valid
  end

  def pre_process(_ctx, import_upload:, **)
    true
  end

  def create_custom_fields(ctx, import_upload:, custom_field_headers:, **)
    # Sometimes we import custom fields. Ensure custom fields get created only if there are records without form_type
    result = true

    if import_upload.processed_row_count.positive?
      # The custom fields have been created. Now we can update the form_type for newly created records
      import_upload.form_type_names.each do |form_type_name|
        # Get the records that do not have a form_type set
        records_wo_form_type = form_type_name.constantize.where(entity_id: import_upload.entity_id, import_upload_id: import_upload.id, form_type_id: nil)

        # If there are records without form_type, we need to set the form_type
        next unless records_wo_form_type.any?

        # Create the custom fields for the form type based on the headers
        custom_fields_created = FormType.save_cf_from_import(custom_field_headers, import_upload, ctx[:form_type_id])

        # Find the form type based on the name - here we assign the last one found
        form_type = import_upload.entity.form_types.where(name: form_type_name).last

        if custom_fields_created.present?
          import_upload.custom_fields_created = custom_fields_created.join(";")
          result = import_upload.save
        end

        Rails.logger.debug { "Updating form_type for #{records_wo_form_type.count} records of type #{form_type_name} to #{form_type&.name}" }
        records_wo_form_type.update_all(form_type_id: form_type.id) if form_type.present?
      end
    end
    result
  end

  def post_process(_ctx, import_upload:, **)
    # Update the counter caches
    if defer_counter_culture_updates
      # if specific FixCountsJob exists, use it
      # This is needed as calling multiple jobs with perform later leads to bug in rollups - the values for some remittances are not rolled up.
      # The specific job will ensure that the rollups are done correctly
      job_class_name = "Import#{import_upload.model_class.to_s.pluralize}FixCountsJob"
      if Object.const_defined?(job_class_name)
        job_class = Object.const_get(job_class_name)

        # Enqueue the job
        job_class.perform_later(import_upload.id)
      else
        Rails.logger.debug { "#{job_class_name} does not exist." }
        ImportFixCountsJob.perform_later(import_upload.id)
      end
    end
    true
  end

  def cleanup(_ctx, import_upload:, **)
    false
  end

  # get header row without the mandatory *
  def get_headers(headers)
    # The headers are transformed by strip, squeeze and titleize and then stripped of *
    ret_headers = headers.compact.each { |x| x&.delete!("*") }.map { |h| h&.downcase&.strip&.squeeze(" ")&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end

  private

  def process_rows(import_upload, headers, data, ctx)
    Rails.logger.debug { "##### process_rows #{data.count}" }
    custom_field_headers = headers - standard_headers
    # Some imports require some custom fields to be ignored, specifically those imports created from the downloaded data, as downloaded data may have additional columns that are not part of the import
    custom_field_headers -= ignore_headers if respond_to?(:ignore_headers)

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
          sanitized_row = row[..(headers.length - 1)].map { |x| x&.to_s&.strip&.squeeze(" ") }
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

    import_upload.save!
    # Save the results file
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
  end

  def process_row(headers, custom_field_headers, row, import_upload, ctx)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_row(user_data, import_upload, custom_field_headers, ctx)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue ActiveRecord::Deadlocked => e
      import_upload.status = "Deadlock: #{e.message}"
      import_upload.error_text = e.backtrace
      import_upload.save
      raise e
    rescue StandardError => e
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      row << "Error #{e.message}"
      row << e.backtrace
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end

  def setup_custom_fields(user_data, model, custom_field_headers)
    custom_field_headers -= ["Update Only"]
    # Some imports require some custom fields to be ignored, specifically those imports created from the downloaded data, as downloaded data may have additional columns that are not part of the import
    custom_field_headers -= ignore_headers if respond_to?(:ignore_headers)

    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      model.properties ||= {}
      custom_field_headers.each do |cfh|
        Rails.logger.debug { "### setup_custom_fields: processing #{cfh}" }
        model.properties[FormCustomField.to_name(cfh)] = user_data[cfh] if cfh.present? # && user_data[cfh].present?
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

  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end
end
