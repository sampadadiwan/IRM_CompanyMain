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
      missing_headers = []
      standard_headers.each do |header_name|
        next if headers.include?(header_name.downcase.strip.squeeze(" ").titleize)

        missing_headers << header_name
      end

      if missing_headers.any?
        import_upload.status = "Column(s) not found: #{missing_headers.join(', ')}"
        import_upload.failed_row_count = import_upload.total_rows_count
        import_upload.save
        valid = false
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
        # Ensure the model has a form_type_id field
        next unless form_type_name.constantize.method_defined?(:form_type_id)

        # Get the records that do not have a form_type set
        form_type_name.constantize.where(entity_id: import_upload.entity_id, import_upload_id: import_upload.id, form_type_id: nil)

        # If this is an import for MULTIPLE_FORM_TYPES_ALLOWED, then skip creating custom fields, as these models can have multiple form types
        unless import_upload.import_type.in?(FormType::MULTIPLE_FORM_TYPES_ALLOWED)
          # Create the custom fields for the form type based on the headers. This is idempotent, so will not create duplicates, but will update the form type with extra custom fields if needed
          custom_fields_created = FormType.save_cf_from_import(custom_field_headers, import_upload, ctx[:form_type_id])
          import_upload.custom_fields_created = custom_fields_created.join(";") if custom_fields_created.present?
        end

        result = import_upload.save
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

  # Normalise a single spreadsheet cell.
  # Files pasted together from Word/web pages routinely carry non-breaking spaces (U+00A0)
  # and other unicode blanks. String#strip only removes ASCII whitespace, so those
  # characters survive and silently break exact-match lookups such as
  # entity.funds.where(name: "\u00A0Artha Fund IV"), which then returns nil.
  #
  # [[:blank:]] and not [[:space:]]: blank covers spaces and tabs including the
  # unicode ones, while leaving newlines alone. Some cells legitimately hold
  # multi-line text - a fund formula body is Ruby source, and folding its newlines
  # into spaces joins two statements into one line and makes it unparseable.
  def sanitize_cell(value)
    return nil if value.nil?

    value.to_s.gsub(/[[:blank:]]/, " ").strip.squeeze(" ")
  end

  # get header row without the mandatory *
  def get_headers(headers)
    # The headers are transformed by strip, squeeze and titleize and then stripped of *
    ret_headers = headers.compact.each { |x| x&.delete!("*") }.map { |h| sanitize_cell(h)&.downcase&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end

  private

  def process_rows(import_upload, headers, data, ctx)
    Rails.logger.debug { "##### process_rows #{data.count}" }
    custom_field_headers = headers - standard_headers
    # Some imports require some custom fields to be ignored, specifically those imports created from the downloaded data, as downloaded data may have additional columns that are not part of the import
    ignore_headers.each { |h| custom_field_headers.delete(h) } if respond_to?(:ignore_headers)

    ctx[:custom_field_headers] = custom_field_headers

    # When a fail_fast importer hits a failed row, this holds the 1-based row number that failed
    stopped_at = nil

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
          sanitized_row = row[..(headers.length - 1)].map { |x| sanitize_cell(x) }

          # Fail fast: an earlier row failed, so skip the remaining rows as they may depend on it (eg a Sell based on a failed Buy)
          if stopped_at
            sanitized_row << "Skipped - import stopped as row #{stopped_at} failed"
            import_upload.failed_row_count += 1
            sheet.add_row(sanitized_row)
            next
          end

          # Ensure the Audit trail is created as the user who uploaded the file
          success = Audited.audit_class.as_user(import_upload.user) do
            process_row(headers, custom_field_headers, sanitized_row, import_upload, ctx)
          end
          # If this is a ShareholderPosition import, allow the importer to inject a computed Fully Dilluted % into the sanitized row
          if import_upload.import_type == "ShareholderPosition"
            fd_index = headers.index("Fully Dilluted %") || headers.index("Fully Diluted %")
            if fd_index && fd_index >= 0
              computed = import_upload.instance_variable_get(:@last_row_computed_percent)
              sanitized_row[fd_index] = computed if computed.present?
            end
          end
          # add row to results sheet
          sheet.add_row(sanitized_row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?

          # Stop processing further rows if this importer requires fail fast and the row failed
          if fail_fast && !success
            stopped_at = idx + 1
            import_upload.status = "Import stopped: row #{stopped_at} failed; remaining rows skipped"
          end
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
        # Explicit boolean so process_rows can detect a failed row for fail_fast importers
        true
      else
        import_upload.failed_row_count += 1
        # save_row returned falsy without raising, so there is no message to show.
        # Say that plainly rather than leaving a bare "Error" in the results sheet.
        row << "Error - the row could not be saved. Check that every record it refers to exists."
        false
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
      false
    end
  end

  def setup_custom_fields(user_data, model, custom_field_headers, form_type: nil)
    # Ensure that we have the form type for the MULTIPLE_FORM_TYPES_ALLOWED
    if form_type.nil? && FormType::MULTIPLE_FORM_TYPES_ALLOWED.include?(model.class.name)
      raise "Form Type must be specified for #{model.class.name} when setting up custom fields"
    elsif form_type.present?
      # Create a map of column header to form custom field for faster lookup
      fcf_label_map = custom_field_header_map(form_type)
    end

    custom_field_headers.delete("Update Only")
    custom_field_headers.delete("Id")
    # Some imports require some custom fields to be ignored, specifically those imports created from the downloaded data, as downloaded data may have additional columns that are not part of the import
    ignore_headers.each { |h| custom_field_headers.delete(h) } if respond_to?(:ignore_headers)

    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive? && model.respond_to?(:properties)
      model.properties ||= {}
      custom_field_headers.each do |cfh|
        Rails.logger.debug { "### setup_custom_fields: processing #{cfh}" }
        next if cfh.blank? # && user_data[cfh].present?

        fcf = fcf_label_map[custom_field_header_key(cfh)] if form_type.present?
        json_fields_key = if fcf.present?
                            # Get the json fields key from the form custom field name based on the label
                            fcf.name
                          elsif form_type.present?
                            # In the tests we may not have created the custom fields yet, so allow that, but in the real world we should raise an error
                            Rails.env.test? ? FormCustomField.to_name(cfh) : raise("Custom field #{cfh} not found in form type #{form_type.name} (tag #{form_type.tag})")
                          else
                            # Create the json fields key from the header
                            FormCustomField.to_name(cfh)
                          end
        # Set the custom field value
        model.json_fields[json_fields_key] = user_data[cfh]
      end
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Maps a normalised column header to its form custom field, keyed on both the label and the name.
  # Keyed on human_label, not label: a Label left blank in the UI is stored as "" (or nil), yet the
  # screens and the upload template (generate_upload_xlsx) show name.humanize.titleize - keying on the
  # raw label collapsed every such field onto one "" key and no column could match.
  # Keys go through the same titleize as get_headers, which turns "-" and "_" into spaces, so a label
  # like "Pre-Money Valuation" or "udr_1" still matches its own column.
  # The name is also accepted as it is shown as "Import Column Name" on the form type page.
  # When keys collide, an explicit label beats a label derived from the name, which beats the name -
  # so a column that matched an explicitly labelled field before still resolves to that same field.
  def custom_field_header_map(form_type)
    fields = form_type.form_custom_fields.to_a
    explicit, derived = fields.partition { |fcf| fcf.label.present? }
    by_name = fields.index_by { |fcf| custom_field_header_key(fcf.name) }
    by_derived_label = derived.index_by { |fcf| custom_field_header_key(fcf.human_label) }
    by_explicit_label = explicit.index_by { |fcf| custom_field_header_key(fcf.label) }
    by_name.merge(by_derived_label).merge(by_explicit_label)
  end

  # Squeezed again after titleize: get_headers squeezes first, so "Photo - Joint Holder" arrives as
  # "Photo   Joint Holder" once titleize has turned the "-" into a space.
  def custom_field_header_key(header)
    sanitize_cell(sanitize_cell(header)&.downcase&.titleize).to_s.downcase
  end

  def setup_exchange_rate(model, user_data)
    as_of = parse_date_cell(user_data, "As Of")
    ExchangeRate.create(from: user_data["From Currency"], to: user_data["To Currency"], as_of:, rate: user_data["Exchange Rate"], entity_id: model.entity_id, notes: "Imported with #{model}")
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
      # Skip trailing blank rows rather than sorting a nil As Of below, and name
      # the sheet in the error when a rate carries an unparseable date
      next if exchange_rate.values.all? { |v| v.to_s.strip.blank? }

      begin
        exchange_rate["As Of"] = parse_date_cell(exchange_rate, "As Of", required: true)
      rescue StandardError => e
        raise "Exchange Rates sheet, row #{idx + 1}: #{e.message}"
      end

      exchange_rates << exchange_rate
    end

    # Sort by the as_of date
    exchange_rates.sort_by { |er| er["As Of"] }
  end

  def stz(val)
    val&.strip&.squeeze(" ")
  end

  # ── Cell helpers ────────────────────────────────────────────────────────────
  # A row that fails must say which column is wrong. Reading a cell straight out
  # of user_data and calling strip/downcase/split on it raises a bare
  # NoMethodError when the cell is empty, which tells the user nothing about
  # what to fix. These helpers keep the failure message anchored to the column.

  # Fetch a cell value. Pass required: true to reject a blank cell by name.
  def cell(user_data, column, required: false)
    value = user_data[column]
    raise "#{column} must be specified" if required && value.to_s.strip.blank?

    value
  end

  # Yes/No flag columns. A blank cell is false rather than a NoMethodError.
  def flag?(value)
    %w[yes true y].include?(value.to_s.strip.downcase)
  end

  # Parse a date cell. Date.local_parse falls back to Date.parse, which reports
  # "no implicit conversion of nil into String" for a blank cell and "invalid
  # date" for a malformed one - neither names the column, so translate both.
  def parse_date_cell(user_data, column, required: false)
    raw = user_data[column]

    if raw.to_s.strip.blank?
      raise "#{column} must be specified" if required

      return nil
    end

    # Roo hands back real Date/Time objects for date formatted cells - convert those
    # directly rather than round tripping them through the string parser
    return raw.to_date if !raw.is_a?(String) && raw.respond_to?(:to_date)

    begin
      Date.local_parse(raw.strip)
    rescue StandardError
      raise "#{column} '#{raw}' is not a valid date. Use the format #{date_format_example}"
    end
  end

  # A sample date in the locale's format, so the user has something to copy
  def date_format_example
    Time.zone.today.strftime(I18n.t("date.formats.default"))
  end

  def defer_counter_culture_updates
    false
  end

  # When true, the import stops at the first failed row and skips all remaining rows.
  # Override in importers where later rows can depend on earlier ones (eg PortfolioInvestment Sells based on Buys)
  def fail_fast
    false
  end

  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end

  # Finds a file by name inside a directory, matching case-insensitively.
  # Returns the full path if found, or nil if not found.
  def find_case_insensitive_file(dir, target_file_name)
    return nil if dir.blank? || target_file_name.blank?

    # Try to find a case-insensitive match in the given directory
    matched_entry = Dir.children(dir).find { |f| f.casecmp?(target_file_name) }
    return File.join(dir, matched_entry) if matched_entry

    # Fallback: return path assuming exact name (may not exist)
    File.join(dir, target_file_name)
  end

  # Given a row we are importing ie user_data, find the form type for the row
  def get_form_type(import_upload, user_data, form_type_name: nil)
    name = if import_upload.import_type == "InvestorKyc"
             %w[IndividualKyc NonIndividualKyc]
           else
             [import_upload.import_type]
           end

    @form_types ||= import_upload.entity.form_types.where(name: name).index_by { |ft| "#{ft.name}-#{ft.tag}" }
    # Find the form type based on the form_type_name and form tag
    form_tag = user_data["Form Tag"]&.strip
    raise "Form Tag not specified" if form_tag.blank?

    # If form_type_name is not specified, use the import_upload.import_type
    form_type_name ||= import_upload.import_type
    form_type = @form_types["#{form_type_name}-#{form_tag}"]
    raise "Form Type not found for #{form_type_name} with tag #{form_tag}" if form_type.nil?

    # Return the form type
    form_type
  end
end
