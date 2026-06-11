class ImportDealInvestorService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDealInvestor)
  step :save_results_file

  # Overrides ImportServiceBase#read_file to parse the three-sheet template:
  #   Sheet "Deal Investors" — main investor data
  #   Sheet "Deal Steps"     — activity status overrides (optional)
  #   Sheet "Notes"          — note records per investor (optional)
  def read_file(ctx, import_file:, import_upload:, **)
    workbook = Roo::Spreadsheet.open(import_file.path)

    ctx[:deal_investors_sheet] = parse_sheet(workbook, "Deal Investors")
    ctx[:deal_steps_sheet]     = parse_sheet_optional(workbook, "Deal Steps")
    ctx[:notes_sheet]          = parse_sheet_optional(workbook, "Notes")

    import_upload.status              = nil
    import_upload.error_text          = nil
    import_upload.failed_row_count    = 0
    import_upload.processed_row_count = 0
    import_upload.total_rows_count    = count_data_rows(ctx)
    import_upload.save

    true
  rescue StandardError => e
    Rails.logger.error e.message
    raise e
  end

  private

  # Returns { headers: [...], data: [[...], ...] } for the named sheet.
  # data[0] is the header row; data[1..] are data rows.
  def parse_sheet(workbook, sheet_name)
    sheet   = workbook.sheet(sheet_name)
    headers = get_headers(sheet.row(1))
    data    = sheet.map { |row| row }
    { headers: headers, data: data }
  end

  # Like parse_sheet but returns nil if the sheet is absent.
  def parse_sheet_optional(workbook, sheet_name)
    parse_sheet(workbook, sheet_name)
  rescue RangeError, TypeError
    nil
  end

  def count_data_rows(ctx)
    # Each sheet: total rows minus 1 header row; floor at 0.
    [ctx[:deal_investors_sheet][:data].length - 1, 0].max +
      (ctx[:deal_steps_sheet]&.dig(:data)&.then { |d| [d.length - 1, 0].max } || 0) +
      (ctx[:notes_sheet]&.dig(:data)&.then { |d| [d.length - 1, 0].max } || 0)
  end
end
