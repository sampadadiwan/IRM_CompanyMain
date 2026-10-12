# Upload of an external administrator's NAV: one draft per row, source "uploaded". A row whose
# NAV ÷ units differs from its NAV per unit by more than 0.01 is rejected.
# The import upload's owner is the evergreen fund.
# Worked examples H5, X7 — openspec/changes/open-ended-funds/design.md#worked-examples
class ImportFundNav < ImportUtil
  # Headers as ImportUtil normalises them (titleized): "NAV Date" in the sheet reads as "Nav Date"
  STANDARD_HEADERS = ["Unit Class", "Nav Date", "Nav", "Units Outstanding", "Nav Per Unit"].freeze
  TOLERANCE = BigDecimal("0.01")

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    fund = import_upload.owner
    raise "Upload NAVs from an evergreen fund" unless fund.is_a?(Fund) && fund.evergreen?

    unit_type = row_data["Unit Class"].to_s.strip
    raise "#{unit_type} is not a unit class of #{fund.name}" unless fund.unit_types_list.include?(unit_type)

    nav_date = parse_date(row_data["Nav Date"])
    nav = to_d(row_data["Nav"])
    units = to_d(row_data["Units Outstanding"])
    per_unit = to_d(row_data["Nav Per Unit"])
    # Worked example X7
    if units.zero? || ((nav / units) - per_unit).abs > TOLERANCE
      raise "NAV per unit does not equal NAV ÷ units outstanding (#{per_unit.to_s('F')} vs #{units.zero? ? 'no units' : (nav / units).round(4).to_s('F')})"
    end

    # X117: liabilities above assets — refused with the reason
    raise FundNav.negative_message(fund, unit_type, nav_date, nav * 100) if nav.negative? || per_unit.negative?

    existing = FundNav.find_by(fund_id: fund.id, unit_type:, nav_date:)
    raise "An approved NAV exists for #{unit_type} on #{nav_date} — reopen it first" if existing&.approved?

    fund_nav = existing || FundNav.new(fund_id: fund.id, unit_type:, nav_date:)
    # Replacing a computed draft: drop its lines and overrides, which no longer add up to the upload
    FundNav::LINES.each { |line| fund_nav["#{line}_cents"] = 0 } if fund_nav.persisted?
    fund_nav.overrides = {}
    fund_nav.assign_attributes(entity_id: fund.entity_id, status: "draft", source: "uploaded", import_upload_id: import_upload.id,
                               prepared_by_id: import_upload.user_id, nav_cents: nav * 100, units_outstanding: units,
                               nav_per_unit_cents: per_unit * 100, nav_per_unit_before_perf_cents: per_unit * 100,
                               breakdown: { "source" => "Uploaded by #{import_upload.user&.full_name}" })
    fund_nav.save!
    EvergreenAlerts.nav_drafted(fund_nav)
    true # ImportUtil counts a falsy return as a failed row
  end

  # X116: a file listing the same class and NAV date twice is refused as a whole — which row is
  # right can't be guessed, and loading one silently would hide the other
  def pre_process(_ctx, import_upload:, headers:, data:, **)
    cls = headers.index("Unit Class")
    date = headers.index("Nav Date")
    return true unless cls && date

    keys = data.drop(1).map { |row| [row[cls].to_s.strip, safe_date(row[date])] }
    dups = keys.tally.select { |_, n| n > 1 }.keys
    return true if dups.empty?

    list = dups.map { |c, d| "Class #{c} on #{d.is_a?(Date) ? I18n.l(d, format: :day_month_year) : d}" }.to_sentence
    import_upload.update(status: "Refused: #{list} appears more than once — keep one row per class and date, then upload again",
                         failed_row_count: import_upload.total_rows_count)
    false
  end

  private

  # A date, or the raw text when it doesn't parse (that row then fails on its own)
  def safe_date(value)
    parse_date(value)
  rescue ArgumentError, TypeError
    value.to_s
  end

  def to_d(value)
    value.to_s.delete(",").strip.to_d
  end

  def parse_date(value)
    value.is_a?(Date) ? value : Date.parse(value.to_s)
  end
end
