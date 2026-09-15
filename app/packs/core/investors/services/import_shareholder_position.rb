class ImportShareholderPosition < ImportUtil
  STANDARD_HEADERS = ["ShareHolder", "As Of"].freeze
  # The Portfolio Company column is mandatory but its header may be named either of these -
  # validated separately from STANDARD_HEADERS since either alias satisfies the requirement.
  PORTFOLIO_COMPANY_HEADER_ALIASES = ["Portfolio Company", "Stakeholder"].freeze
  # A Fully Dilluted % on its own is only ever a relative weight - it identifies no real
  # share/unit count. Only a Fully Dilluted Quantity (a real share/unit count, from which % is
  # calculated - see computed_percent_points_from_quantity), alone or together with a Fully Dilluted %,
  # is accepted; a bare % with no Quantity is rejected (see validate_headers/save_row below).
  FULLY_DILUTED_PERCENTAGE_HEADER_ALIASES = ["Fully Dilluted %", "Fully Diluted %"].freeze
  FULLY_DILUTED_QUANTITY_HEADER_ALIASES = ["Fully Dilluted Quantity", "Fully Diluted Quantity"].freeze
  # Every row's Fully Dilluted % for the same Portfolio Company/Stakeholder + As Of round is a
  # share of that one round's 100% cap table snapshot. Rounding in the source spreadsheet (%s
  # typed to 2 decimal places, etc) means the totals rarely land on exactly 100.0 - this is the
  # slack allowed before a combo is rejected as inconsistent.
  FULLY_DILUTED_PERCENTAGE_TOTAL_TOLERANCE = 0.01

  def standard_headers
    STANDARD_HEADERS
  end

  # Every upload must identify the Portfolio Company per row (via a "Portfolio Company" or
  # "Stakeholder" column), regardless of whether the upload was initiated from a specific
  # portfolio company's page. This keeps the import behavior explicit and consistent, and allows
  # a single file to contain positions for multiple companies at once.
  def validate_headers(_ctx, import_upload:, headers:, **)
    valid = super
    return valid unless valid

    unless PORTFOLIO_COMPANY_HEADER_ALIASES.any? { |name| headers.include?(name) }
      import_upload.status = "Column(s) not found: Portfolio Company (or Stakeholder)"
      import_upload.failed_row_count = import_upload.total_rows_count
      import_upload.save
      return false
    end

    # A Fully Dilluted Quantity header is always required now - a Fully Dilluted % header on its
    # own (with no Quantity header at all) can never produce a valid row, since every row would
    # fail the bare-%-without-Quantity check in save_row below anyway.
    return true if FULLY_DILUTED_QUANTITY_HEADER_ALIASES.any? { |name| headers.include?(name) }

    import_upload.status = "Column(s) not found: Fully Dilluted Quantity"
    import_upload.failed_row_count = import_upload.total_rows_count
    import_upload.save
    false
  end

  # Pre-scan the uploaded sheet to compute the total Fully Diluted Quantity for each Portfolio
  # Company/Stakeholder + As Of round (never across the whole sheet - a file can hold multiple
  # companies/rounds, each with its own independent 100% total), and (only for this
  # ShareholderPosition importer) verify that any typed-in Fully Dilluted %s add up to 100% for
  # each of those same combos. A mismatch means the snapshot as uploaded is internally
  # inconsistent, so the whole upload is rejected here before any row is saved - the same way a
  # missing required column is rejected in validate_headers.
  def pre_process(_ctx, import_upload:, headers:, data:, **)
    fd_index = header_index(headers, "Fully Dilluted Quantity", "Fully Diluted Quantity")
    fd_totals = Hash.new(0.0)

    if fd_index
      data.each_with_index do |row, idx|
        next if idx.zero?

        cells = row[0...headers.length]
        user_data = headers.zip(cells).to_h
        qty = pick_value(user_data, "Fully Dilluted Quantity", "Fully Diluted Quantity")
        next if qty.blank?

        portfolio_company_name = pick_value(user_data, "Portfolio Company", "Stakeholder")
        row_as_of = pick_value(user_data, "As Of", "As of", "as of", "Position Date", "position_date")
        group_key = [portfolio_company_name, round_key_for(row_as_of)]
        begin
          fd_totals[group_key] += qty.to_s.gsub(',', '').to_f
        rescue StandardError
          nil
        end
      end
    end

    import_upload.instance_variable_set(:@fd_totals, fd_totals)

    mismatches = percentage_total_errors(headers, data)
    duplicates = duplicate_row_errors(headers, data)

    errors = []
    errors << "Fully Dilluted % must total 100% for each Portfolio Company/Stakeholder + As Of combination. Found: #{mismatches.join('; ')}" if mismatches.any?
    errors << "Duplicate ShareHolder/Portfolio Company/As Of/Instrument/Category combination(s) found: #{duplicates.join('; ')}" if duplicates.any?

    if errors.any?
      import_upload.status = errors.join(' ')
      import_upload.failed_row_count = import_upload.total_rows_count
      import_upload.save
      return false
    end

    true
  end

  # Groups every row's typed-in Fully Dilluted % by (Portfolio Company/Stakeholder, As Of round)
  # and flags any combo whose %s don't add up to ~100% (a combo with no % typed in at all is
  # skipped - there's nothing to check). Returns an array of "Company / Round: NN%" strings,
  # empty when every combo is consistent. Pure/read-only - shared by pre_process (the real
  # import's hard gate) and ImportUploadsController#validate_upload (the same check run the
  # moment a file is chosen, before Save is ever clicked - see xlsx_preview_controller.js).
  def percentage_total_errors(headers, data)
    percentage_totals = Hash.new(0.0)

    data.each_with_index do |row, idx|
      next if idx.zero?

      cells = row[0...headers.length]
      user_data = headers.zip(cells).to_h

      percentage_raw = pick_value(user_data, "Fully Dilluted %", "Fully Diluted %")
      next if percentage_raw.blank?

      percentage_points = parse_percentage_points(percentage_raw)
      next if percentage_points.nil?

      portfolio_company_name = pick_value(user_data, "Portfolio Company", "Stakeholder")
      row_as_of = pick_value(user_data, "As Of", "As of", "as of", "Position Date", "position_date")
      group_key = [portfolio_company_name, round_key_for(row_as_of)]
      percentage_totals[group_key] += percentage_points
    end

    percentage_totals.filter_map do |(portfolio_company_name, round_key), sum|
      next if (sum - 100.0).abs <= FULLY_DILUTED_PERCENTAGE_TOTAL_TOLERANCE

      "#{portfolio_company_name.presence || 'Unknown'} / #{round_key.presence || 'Unknown'}: #{format_percentage_points(sum.round(2))}"
    end
  end

  # Flags rows that share the exact same ShareHolder, Portfolio Company/Stakeholder, As Of round,
  # Instrument and Category - the same position typed in twice under the same identity,
  # which would otherwise silently update/duplicate itself in save_row. A row with nothing typed
  # in any of those columns identifies nothing to de-duplicate against and is skipped. Returns an
  # array of "ShareHolder / Portfolio Company / Round / Instrument / Category (Nx)"
  # strings, empty when every combination is unique. Pure/read-only - shared by pre_process (the
  # real import's hard gate) and ValidateShareholderPositionPercentages (the same check run the
  # moment a file is chosen, before Save is ever clicked - see
  # shareholder_position_percentage_check_controller.js).
  def duplicate_row_errors(headers, data)
    seen = Hash.new(0)

    data.each_with_index do |row, idx|
      next if idx.zero?

      cells = row[0...headers.length]
      user_data = headers.zip(cells).to_h

      investor_name = pick_value(user_data, 'ShareHolder', 'Shareholder')
      portfolio_company_name = pick_value(user_data, 'Portfolio Company', 'Stakeholder')
      row_as_of = pick_value(user_data, 'As Of', 'As of', 'as of', 'Position Date', 'position_date')
      instrument = pick_value(user_data, 'Instrument', 'instrument')&.to_s&.strip
      category = pick_value(user_data, 'Category', 'category')&.to_s&.strip

      next if investor_name.blank? && portfolio_company_name.blank? && row_as_of.blank? && instrument.blank? && category.blank?

      group_key = [investor_name, portfolio_company_name, round_key_for(row_as_of), instrument, category]
      seen[group_key] += 1
    end

    seen.filter_map do |(investor_name, portfolio_company_name, round_key, instrument, category), count|
      next if count <= 1

      "#{investor_name.presence || 'Unknown'} / #{portfolio_company_name.presence || 'Unknown'} / #{round_key.presence || 'Unknown'} / #{instrument.presence || 'Unknown'} / #{category.presence || 'Unknown'} (#{count}x)"
    end
  end

  # After this upload's rows are saved (both brand-new approved rows and staged unapproved
  # updates), check whether each Portfolio Company + Round this upload touched still totals
  # ~100% for Fully Dilluted % once combined with the rest of that round's positions - i.e. the
  # already-approved holdings this upload didn't touch, plus this upload's own new/staged rows
  # standing in for whatever they're replacing (see ShareholderPosition.round_percentage_total).
  # This is different from percentage_total_errors above: that check only ever looks at the
  # uploaded rows in isolation, so a file that's internally consistent (its own rows sum to 100%)
  # can still throw a round off once merged with pre-existing approved data for Shareholders the
  # file didn't mention at all. Never blocks the upload itself (the rows are already saved) - it
  # only flags which Portfolio Company/Round combos need a closer look before their pending
  # updates are approved (see ShareholderPositionPolicy#approve? / ShareholderPositionApprover),
  # and annotates the downloadable results sheet so the offending rows can be found at a glance
  # (see annotate_results_file_with_round_mismatches).
  def round_percentage_total_errors_for_upload(import_upload)
    new_rows = ShareholderPosition.where(import_upload_id: import_upload.id).where.not(fully_diluted_percentage: nil)
    return [] if new_rows.empty?

    groups = new_rows.group_by { |row| [row.portfolio_company_id, row.round_name, row.position_date] }

    groups.filter_map do |(portfolio_company_id, round_name, position_date), _rows|
      total = ShareholderPosition.round_percentage_total(portfolio_company_id: portfolio_company_id, round_name: round_name, position_date: position_date)
      next if (total - 100.0).abs <= FULLY_DILUTED_PERCENTAGE_TOTAL_TOLERANCE

      portfolio_company_name = Investor.find_by(id: portfolio_company_id)&.investor_name
      round_key = round_label(position_date, round_name)
      {
        portfolio_company_name: portfolio_company_name,
        round_key: round_key,
        message: "#{portfolio_company_name.presence || 'Unknown'} / #{round_key.presence || 'Unknown'}: #{format_percentage_points(total.round(2))} combined with existing data"
      }
    end
  end

  # Reopens the "Import Results" sheet process_rows (ImportUtil) already wrote to
  # /tmp/import_result_#{id}.xlsx (before ImportServiceBase#save_results_file attaches it to
  # import_upload.import_results), and appends a note to every row belonging to a mismatched
  # Portfolio Company/Round combo - so downloading that sheet shows exactly which uploaded lines
  # are part of a round that doesn't total 100% once combined with existing data.
  def annotate_results_file_with_round_mismatches(import_upload, mismatches)
    path = "/tmp/import_result_#{import_upload.id}.xlsx"
    return unless File.exist?(path)

    mismatch_by_key = mismatches.index_by { |mismatch| [mismatch[:portfolio_company_name], mismatch[:round_key]] }

    sheet = Roo::Spreadsheet.open(path).sheet(0)
    headers = sheet.row(1)
    annotated_rows = (2..sheet.last_row).map do |row_number|
      row = sheet.row(row_number)
      user_data = headers.zip(row).to_h
      portfolio_company_name = pick_value(user_data, "Portfolio Company", "Stakeholder")
      round_key = round_key_for(pick_value(user_data, "As Of", "As of", "as of", "Position Date", "position_date"))
      mismatch = mismatch_by_key[[portfolio_company_name, round_key]]
      next row unless mismatch

      row.dup.tap { |r| r[-1] = "#{r[-1]} | ROUND MISMATCH: Fully Dilluted % totals #{mismatch[:message]} instead of 100%" }
    end

    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Import Results") do |worksheet|
      worksheet.add_row(headers)
      annotated_rows.each { |row| worksheet.add_row(row) }
    end
    File.binwrite(path, package.to_stream.read)
  rescue StandardError => e
    Rails.logger.error { "Could not annotate results file with round mismatches for import_upload=#{import_upload.id}: #{e.message}" }
  end

  # Runs after every row is saved (see ImportUtil#post_process, which this calls via super to
  # keep the counter-cache behavior every other importer relies on) - the combined-with-existing
  # round check can only run once this upload's own rows actually exist in the DB.
  def post_process(ctx, import_upload:, **)
    mismatches = round_percentage_total_errors_for_upload(import_upload)
    if mismatches.any?
      annotate_results_file_with_round_mismatches(import_upload, mismatches)
      message = "Fully Dilluted % must total 100% for each Portfolio Company/Round combination once combined with existing data. Found: #{mismatches.pluck(:message).join('; ')}"
      import_upload.status = [import_upload.status.presence, message].compact.join(' ')
      import_upload.save
    end
    super
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    investor_name, fully_diluted_percentage, fully_diluted_percentage_points, fully_diluted_quantity, as_of, round_name, portfolio_company_name, fund_name, position_type, position_amount, category, subgroup, instrument, quantity_actual = get_data(user_data, custom_field_headers, import_upload)

    # The persisted % for this row: prefer the typed Fully Dilluted %, and only compute one from
    # the Fully Dilluted Quantity (÷ pre-scanned total for this row's own Portfolio
    # Company/Stakeholder + As Of round - see pre_process) when no % was typed in.
    group_key = [portfolio_company_name, round_label(as_of, round_name)]
    computed_percentage_points = computed_percent_points_from_quantity(fully_diluted_quantity, import_upload, group_key)
    resolved_percentage_points = fully_diluted_percentage_points.presence || computed_percentage_points

    # A bare Fully Dilluted % with no Fully Dilluted Quantity identifies no real share/unit count
    # for this row - only a Quantity alone, or a Quantity together with a %, is accepted.
    if fully_diluted_percentage.present? && fully_diluted_quantity.blank?
      msg = "Fully Dilluted % cannot be uploaded without a Fully Dilluted Quantity. Upload a Fully Dilluted Quantity alone, or together with a Fully Dilluted %."
      Rails.logger.error { "#{msg} import_upload=#{import_upload&.id}" }
      raise msg
    end

    # The Portfolio Company (or Stakeholder) column is always required and is always taken from
    # the row - the page/owner context the upload was started from is never used as a fallback.
    if portfolio_company_name.blank?
      msg = "Portfolio Company (or Stakeholder) is required for each shareholder position row."
      Rails.logger.error { "#{msg} import_upload=#{import_upload&.id}" }
      raise msg
    end

    portfolio_company = import_upload.entity.investors.portfolio_companies.find_by(investor_name: portfolio_company_name)
    if portfolio_company.blank?
      Rails.logger.debug { "Portfolio Company #{portfolio_company_name} not found for entity #{import_upload.entity_id}" }
      raise "Portfolio Company #{portfolio_company_name} not found for entity #{import_upload.entity_id}"
    end

    # The upload owner/portfolio company is not the shareholder. It is only the company context.
    # Use the row ShareHolder as the investor, and only fall back to the portfolio company if the
    # file omits the shareholder name.
    investor = import_upload.entity.investors.find_by(investor_name: investor_name) if investor_name.present?
    investor ||= portfolio_company if portfolio_company.present?

    if investor.blank?
      Rails.logger.debug { "Investor #{investor_name.presence || 'blank'} not found and no portfolio company fallback available" }
      raise "Investor #{investor_name.presence || 'blank'} not found and no portfolio company fallback available"
    end


    fund = Fund.find_by(name: fund_name, entity_id: import_upload.entity_id) if fund_name.present?

    if fund.blank? && fund_name.present?
      Rails.logger.warn { "Fund #{fund_name} not found for entity #{import_upload.entity_id}; proceeding with nil fund" }
    end

    require_as_of!(as_of, round_name, import_upload)

    debug_info = {
      import_upload_id: import_upload&.id,
      entity_id: import_upload&.entity_id,
      investor_name: investor_name,
      investor_id: investor&.id,
      portfolio_company_id: portfolio_company&.id,
      fund_name: fund_name,
      fund_id: fund&.id,
      position_type: position_type,
      position_amount: position_amount,
      as_of: as_of,
      round_name: round_name,
      category: category,
      fully_diluted_percentage: fully_diluted_percentage,
      fully_diluted_quantity: fully_diluted_quantity
    }

    Rails.logger.debug { "Saving Shareholder Position: #{debug_info.inspect}" }

    # An upload for the same investor/round/instrument as an already-approved position is an
    # update to that position, not a brand-new one. Both a new Quantity Actuals and a new Fully
    # Diluted Quantity/% can shift what other stakeholders/reports rely on, so both are staged as
    # `unapproved` and only take effect once explicitly accepted (see ShareholderPositionApprover
    # / ShareholderPositionsController) - never applied directly to the approved row here.
    existing_approved = ShareholderPosition.find_matching_approved(
      portfolio_company_id: portfolio_company.id,
      investor_label: investor_name.presence,
      investor_id: investor.id,
      instrument: instrument,
      round_name: round_name,
      position_date: as_of
    )

    # Tracks whether this row's Fully Diluted change was staged for approval rather than already
    # in effect, so the results sheet can label the computed % as pending instead of implying it
    # already applies.
    percentage_pending = false

    begin
      if existing_approved
        # A bare "Fully Dilluted %" (no accompanying Fully Dilluted Quantity in this row) is
        # expressed in percentage points (0-100) - a completely different scale to a real
        # share/unit quantity. If the existing approved position already holds a real quantity
        # (i.e. its position_amount is far above anything a percentage could be), staging that
        # raw percentage as the new position_amount would - once accepted - silently replace the
        # real Quantity with a tiny percentage-sized number. So a percentage-only re-upload is
        # only allowed to update a position whose existing value already looks percentage-based
        # (<= 100); it can never overwrite a quantity-based one. Uploading a real Fully Dilluted
        # Quantity is still always required to update a quantity-based position.
        quantity_uploaded = parse_numeric(fully_diluted_quantity)
        percentage_only_update = quantity_uploaded.nil? && existing_approved.position_amount.to_f > 100.5

        if percentage_only_update
          Rails.logger.warn do
            "Skipping Fully Diluted %-only update for #{investor_name} " \
              "(portfolio_company=#{portfolio_company.id}, round=#{round_name || as_of}) - existing " \
              "position_amount=#{existing_approved.position_amount} looks quantity-based; upload a Fully " \
              "Dilluted Quantity to update it."
          end
          position_amount_changed = false
        else
          position_amount_changed = position_amount.present? && !values_equal?(existing_approved.position_amount, position_amount)
        end

        quantity_actual_changed = quantity_actual.present? && !values_equal?(existing_approved.quantity_actual, quantity_actual)
        fully_diluted_percentage_changed = resolved_percentage_points.present? && !values_equal?(existing_approved.fully_diluted_percentage, resolved_percentage_points)

        if position_amount_changed || quantity_actual_changed || fully_diluted_percentage_changed
          ShareholderPosition.create!(
            investor: investor,
            portfolio_company: portfolio_company,
            fund: fund,
            position_type: position_type,
            position_amount: position_amount_changed ? position_amount : existing_approved.position_amount,
            position_date: as_of,
            round_name: round_name,
            category: category,
            subgroup: subgroup,
            instrument: instrument,
            quantity_actual: quantity_actual_changed ? quantity_actual : existing_approved.quantity_actual,
            fully_diluted_percentage: fully_diluted_percentage_changed ? resolved_percentage_points : existing_approved.fully_diluted_percentage,
            import_upload_id: import_upload.id,
            entity_id: import_upload.entity_id,
            investor_label: investor_name.presence,
            status: 'unapproved'
          )
          percentage_pending = position_amount_changed || fully_diluted_percentage_changed
        end
      else
        ShareholderPosition.create!(
          investor: investor,
          portfolio_company: portfolio_company,
          fund: fund,
          position_type: position_type,
          position_amount: position_amount,
          position_date: as_of,
          round_name: round_name,
          category: category,
          subgroup: subgroup,
          instrument: instrument,
          quantity_actual: quantity_actual,
          fully_diluted_percentage: resolved_percentage_points,
          import_upload_id: import_upload.id,
          entity_id: import_upload.entity_id,
          investor_label: investor_name.presence
        )
      end
    rescue StandardError => e
      Rails.logger.error { "Failed saving ShareholderPosition: #{e.class}: #{e.message}; row_data=#{debug_info.inspect}" }
      raise
    end

    # Record the Fully Diluted % the results sheet should show. The typed "Fully Dilluted %" is
    # always trusted first; the % is only derived from the Fully Dilluted Quantity (quantity ÷
    # pre-scanned total) when the row didn't type in a % at all.
    display_percentage = fully_diluted_percentage.presence || format_percentage_points(computed_percentage_points)

    # A staged (unapproved) Fully Diluted change isn't in effect yet - label the computed % as
    # pending so the results sheet doesn't imply it already applies to the cap table.
    display_percentage = "#{display_percentage} (Pending Approval)" if display_percentage.present? && percentage_pending

    import_upload.instance_variable_set(:@last_row_computed_percent, display_percentage)
  end

  def get_data(user_data, _custom_field_headers, import_upload = nil)
    investor_name = pick_value(user_data, 'ShareHolder', 'Shareholder')
    fully_diluted_percentage_raw = pick_value(user_data, 'Fully Dilluted %', 'Fully Diluted %')
    fully_diluted_percentage_points = parse_percentage_points(fully_diluted_percentage_raw)
    fully_diluted_percentage = format_percentage_points(fully_diluted_percentage_points)
    fully_diluted_quantity = pick_value(user_data, 'Fully Dilluted Quantity', 'Fully Diluted Quantity')&.to_s&.strip

    # Only take fund from the row. Do not fall back to upload name (file label/title).
    fund_name = user_data['Fund'].presence
    position_type = user_data['Position Type'].presence || 'Shareholder'
    position_amount = user_data['Position Amount'].presence
    category_raw = pick_value(user_data, 'Category', 'category')

    category = normalize_category(category_raw)
    Rails.logger.error { "Normalized category: #{category}" }
    subgroup = normalize_subgroup(pick_value(user_data, 'Subgroup', 'Sub Group', 'subgroup', 'sub_group'))
    instrument = pick_value(user_data, 'Instrument', 'instrument')&.to_s&.strip
    # Optional, non-mandatory column - a real (non fully-diluted) share/unit quantity for the row.
    quantity_actual = parse_numeric(pick_value(user_data, 'Quantity Actuals', 'Quantity Actual', 'quantity actuals', 'quantity actual'))
    if position_amount.blank?
      # For captable uploads: prefer a genuine uploaded Fully Dilluted Quantity, since it's a real
      # share/unit count that the cap table's "Quantity- fully diluted" column can show as-is and
      # the % stake can be derived from it. Only fall back to the bare Fully Dilluted % (which can
      # only ever produce relative weights, never a real quantity) when no quantity was uploaded.
      position_amount = parse_numeric(fully_diluted_quantity) || fully_diluted_percentage_points
    end

    row_as_of = pick_value(user_data, 'As Of', 'As of', 'as of', 'Position Date', 'position_date')
    as_of = parse_as_of_date(row_as_of)
    # When the "As Of" value isn't a recognizable date (e.g. a free-text round name like
    # "Secondary Sale"), use the raw text directly as the round name instead of a date.
    round_name = as_of.nil? ? row_as_of.to_s.strip.presence : nil

    portfolio_company_name = pick_value(user_data, 'Portfolio Company', 'Stakeholder')

    [investor_name, fully_diluted_percentage, fully_diluted_percentage_points, fully_diluted_quantity, as_of, round_name, portfolio_company_name, fund_name, position_type, position_amount, category, subgroup, instrument, quantity_actual]
  end

  def normalize_category(value)
    raw = value.to_s.strip
    return 'Other' if raw.blank?

    tokens = raw.split(/[\/,|&]/).map { |part| part.to_s.strip }
    tokens << raw

    tokens.each do |token|
      normalized = token.to_s.strip
      next if normalized.blank?

      case normalized.downcase
      when 'founder', 'founders'
        return 'Founder'
      when 'esop', 'employees', 'employee'
        return 'Employee'
      when 'self', 'company', 'portfolio company', 'portfolio_company', 'portfolio-company'
        return 'Self'
      when 'other', 'others'
        return 'Other'
      end
    end

    # The main Group is restricted to Founder/Self/Other/Employee. An unrecognized value is
    # rejected outright (rather than silently bucketed as 'Other') so the uploader gets an
    # actionable error and can fix the file instead of having their category silently discarded.
    raise "Invalid category '#{raw}'. Must be one of Founder, Self, Other, Employee."
  end

  def normalize_subgroup(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    raw
  end

  # Rounds to cents before comparing so a re-upload of an unchanged decimal value (which can
  # differ in floating-point noise past 2 decimal places) is never mistaken for a real update
  # requiring approval.
  def values_equal?(existing_value, new_value)
    existing_value.to_f.round(2) == new_value.to_f.round(2)
  end

  def pick_value(row_hash, *keys)
    keys.each do |key|
      value = row_hash[key]
      return value if value.present?
    end
    nil
  end

  def header_index(headers, *names)
    names.each do |name|
      idx = headers.index(name)
      return idx if idx
    end
    nil
  end

  def parse_numeric(value)
    return nil if value.blank?

    normalized = value.to_s.strip.delete(',').delete('%')
    return nil if normalized.blank?

    Float(normalized)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_as_of_date(value)
    return nil if value.blank?

    return value.to_date if value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)

    # Excel stores dates as serial day numbers from 1899-12-30.
    if value.is_a?(Numeric)
      return Date.new(1899, 12, 30) + value.to_i
    end

    string_value = value.to_s.strip
    return nil if string_value.blank?

    if string_value.match?(/\A\d+(\.\d+)?\z/)
      return Date.new(1899, 12, 30) + string_value.to_f.to_i
    end

    # Each format is paired with a strict regex requiring the exact digit widths the format
    # expects (e.g. a 4-digit %Y). Without this guard, Date.strptime happily consumes fewer
    # digits than a directive implies (or spills extra digits into the next one) - e.g.
    # "31/02/2025" against "%Y/%m/%d" silently parses as year 31, month 02, day 20 instead of
    # being rejected, producing a nonsensical date like "February 0031".
    date_formats = {
      '%d/%m/%Y' => /\A\d{1,2}\/\d{1,2}\/\d{4}\z/,
      '%d-%m-%Y' => /\A\d{1,2}-\d{1,2}-\d{4}\z/,
      '%d/%m/%y' => /\A\d{1,2}\/\d{1,2}\/\d{2}\z/,
      '%d-%m-%y' => /\A\d{1,2}-\d{1,2}-\d{2}\z/,
      '%m/%d/%Y' => /\A\d{1,2}\/\d{1,2}\/\d{4}\z/,
      '%m-%d-%Y' => /\A\d{1,2}-\d{1,2}-\d{4}\z/,
      '%m/%d/%y' => /\A\d{1,2}\/\d{1,2}\/\d{2}\z/,
      '%m-%d-%y' => /\A\d{1,2}-\d{1,2}-\d{2}\z/,
      '%Y-%m-%d' => /\A\d{4}-\d{1,2}-\d{1,2}\z/,
      '%Y/%m/%d' => /\A\d{4}\/\d{1,2}\/\d{1,2}\z/,
      '%d %B %Y' => /\A\d{1,2}\s+[A-Za-z]+\s+\d{4}\z/,
      '%d %b %Y' => /\A\d{1,2}\s+[A-Za-z]+\s+\d{4}\z/,
      '%B %Y' => /\A[A-Za-z]+\s+\d{4}\z/,
      '%b %Y' => /\A[A-Za-z]+\s+\d{4}\z/,
      '%B %d %Y' => /\A[A-Za-z]+\s+\d{1,2}\s+\d{4}\z/,
      '%b %d %Y' => /\A[A-Za-z]+\s+\d{1,2}\s+\d{4}\z/
    }

    date_formats.each do |format, pattern|
      next unless string_value.match?(pattern)

      begin
        return Date.strptime(string_value, format)
      rescue ArgumentError
        next
      end
    end

    # If the value is shaped like a numeric date (e.g. "31/02/2025") but didn't parse under any
    # of the formats above, it's an invalid calendar date (e.g. February 31st) rather than a
    # free-text round name - raise so the user can correct it instead of silently filing it
    # under a nonsense round name.
    if string_value.match?(%r{\A\d{1,4}[/-]\d{1,4}[/-]\d{1,4}\z})
      raise "Invalid date \"#{string_value}\" in As Of column. Please provide a valid calendar date or a round name."
    end

    # Anything left over is treated as a non-date round name rather than guessed at with a
    # loose Date.parse, which can misinterpret arbitrary text (e.g. "Series A 2025") as a date.
    nil
  end

  # A recognizable calendar date becomes a "Month Year" label (matching how the cap table itself
  # groups position_date rows - see _captable.html.erb); anything else is used as a free-text
  # round name as-is. Shared by pre_process's raw-value grouping (round_key_for) and save_row's
  # already-parsed as_of/round_name, so both land on the exact same group key for a given row.
  def round_label(as_of_date, round_name)
    as_of_date ? as_of_date.strftime("%B %Y") : round_name
  end

  # Groups rows the same way get_data derives round_name/as_of, from the row's raw "As Of" cell.
  # Swallows date parsing errors here (an invalid date is reported per-row later via
  # save_row/require_as_of!) so a single bad "As Of" cell can't abort this whole-sheet pre-check.
  def round_key_for(row_as_of)
    as_of = begin
      parse_as_of_date(row_as_of)
    rescue StandardError
      nil
    end
    round_label(as_of, row_as_of.to_s.strip.presence)
  end

  def require_as_of!(as_of_date, round_name = nil, import_upload = nil)
    return if as_of_date.present? || round_name.present?

    msg = "As Of is required for each shareholder position row. Please provide a valid date (e.g. March 2025) or a round name."
    Rails.logger.error { "#{msg} import_upload=#{import_upload&.id}" }
    raise msg
  end

  def parse_percentage_points(value)
    return nil if value.blank?

    string_value = value.to_s.strip
    normalized = string_value.delete(',').delete('%')
    return nil if normalized.blank?

    points = Float(normalized)

    # Excel percentage cells are often read as fractions (0.2 for 20%).
    if points.abs <= 1.0 && !string_value.include?('%')
      points *= 100.0
    end

    points
  rescue ArgumentError, TypeError
    nil
  end

  def format_percentage_points(points)
    return nil if points.nil?

    rounded = points.round(6)
    display = (rounded % 1).zero? ? rounded.to_i.to_s : rounded.to_s
    "#{display}%"
  end

  # Compute percentage points (0-100, unformatted) from quantity using the precomputed total for
  # this row's own Portfolio Company/Stakeholder + As Of round (never the whole sheet - a file
  # can hold multiple companies/rounds, each its own independent 100% total - see pre_process).
  # Used both to persist a real % when no % was typed in, and to render that computed % on the
  # results sheet.
  def computed_percent_points_from_quantity(qty, import_upload, group_key)
    return nil if qty.blank?
    total = import_upload.instance_variable_get(:@fd_totals)&.[](group_key).to_f
    return nil if total <= 0
    begin
      qty.to_s.gsub(',', '').to_f / total * 100.0
    rescue StandardError
      nil
    end
  end

  def import
    # Enqueue job if present. Prefer generic ImportUploadJob pumped elsewhere; keep safe call.
    if Object.const_defined?("ImportShareholderPositionJob")
      ImportShareholderPositionJob.perform_later(@import_upload.id)
    end
  end
end
