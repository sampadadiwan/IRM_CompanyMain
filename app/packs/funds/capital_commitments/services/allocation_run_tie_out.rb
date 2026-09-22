# The fund totals sheet: what one allocation run produced for each entry name, beside the
# fund's own figure for that name, and the difference between them. See
# docs/modules/allocation/allocation_run_review_proposals.md (proposal 3).
#
# Funds keep their books in a spreadsheet outside CapHive and review a run in two steps —
# first the fund totals against that sheet, then a few folios. This is step one.
#
# PERFORMANCE CONTRACT. This class issues NO query of its own against account_entries for the
# sheet itself: the rows are derived in Ruby from AccountEntryReport#name_date_totals, which the
# page has already run (pass 1 of its two aggregate passes — see
# docs/modules/reports/account_entry_report_performance.md). Only two small queries are added,
# both off account_entries: the fund's own figures, and the formula sequence used to order the
# rows. #folios is the one exception and runs only when a reviewer opens a single row.
#
# Rows are grouped by entry name alone, not by (name, entry_type): a fund's spreadsheet has one
# line called "Management Fees", and name is also all pass 1 groups by, so grouping any finer
# would cost another scan to answer a question nobody asked.
class AllocationRunTieOut
  # At most this many folios are listed when a row is opened. A fund with thousands of folios
  # would otherwise render thousands of table rows into a page that is already showing a pivot.
  MAX_FOLIOS = 50

  # Two figures agree when they look the same on screen. The sheet is read at 2 decimal places
  # in major units, so anything that rounds to the same displayed amount is a match — there is
  # no per-fund tolerance to configure and no "differs by 0.001" row to explain.
  DISPLAY_PRECISION = 2

  # dependency_signs: { dependency name => 1 or -1 } — whether the formula adds that total or
  # takes it away, so "NAV" reads as collected minus fees rather than a list of both.
  # top: true when no other total on the sheet is built from this one — a final number.
  # earlier_periods: dependency names read at a date other than the run's own — "Beginning
  # Unfunded Commitment" reads last quarter's "Ending Unfunded Commitment". The edge is real,
  # but the figure shown beside it is this run's, so the view must say so.
  Row = Struct.new(:name, :system_cents, :entry_count, :figure, :sequence, :formula,
                   :dependencies, :dependency_signs, :top, :earlier_periods, keyword_init: true) do
    # The fund's own figure, or nil when nobody has typed one for this name yet.
    def own_cents = figure&.amount_cents

    def entered? = figure.present?

    # Positive means the fund's sheet is higher than ours.
    def difference_cents = entered? ? own_cents - system_cents : nil

    # :match, :differs or :not_entered — what the row's badge says.
    def state
      return :not_entered unless entered?

      rounded(own_cents) == rounded(system_cents) ? :match : :differs
    end

    def match? = state == :match
    def differs? = state == :differs

    # The other rows of this sheet that this row's formula is built from. Resolved once the
    # whole sheet exists, because a dependency is always another row on it. Always an array:
    # a row whose formula has been deleted, or which names nothing this run produced, is
    # ordinary rather than exceptional, and a view should not have to guard against nil.
    def dependencies = self[:dependencies] || []

    def dependencies? = dependencies.any?

    def sign_of(dependency) = (self[:dependency_signs] || {}).fetch(dependency.name, 1)

    def earlier_period?(dependency) = Array(self[:earlier_periods]).include?(dependency.name)

    private

    # Major units at the precision the sheet is read at.
    def rounded(cents) = (cents.to_d / 100).round(DISPLAY_PRECISION)
  end

  # @param report [AccountEntryReport] the page's report, already scoped to the run
  # @param fund [Fund]
  # @param allocation_run [AllocationRun]
  # with_figures: load the fund's own typed figures (the tie-out sheet). Off by default — the
  # Dependencies tab never shows them and was paying a query for them anyway.
  def initialize(report:, fund:, allocation_run:, with_figures: false)
    @report = report
    @fund = fund
    @allocation_run = allocation_run
    @with_figures = with_figures
  end

  # One row per entry name the run produced, in the fund's own formula order — that is the order
  # its staff think in, and it keeps a name next to the names it is derived from. Names whose
  # formula has since been deleted sort last, alphabetically among themselves.
  # @return [Array<Row>]
  def rows
    @rows ||= begin
      totals = totals_by_name
      figures = @with_figures ? figures_by_name : {}
      sequences = sequence_by_name(totals.keys)

      rows = totals.map do |name, (system_cents, entry_count)|
        Row.new(name: name, system_cents: system_cents, entry_count: entry_count,
                figure: figures[name], sequence: sequences.dig(name, :sequence),
                formula: sequences.dig(name, :formula), dependencies: [])
      end.sort_by { |row| [row.sequence || Float::INFINITY, row.name] }

      link_dependencies(rows)
      mark_top_level(rows)
      rows
    end
  end

  def any_rows? = rows.any?

  def entered_count = rows.count(&:entered?)
  def match_count = rows.count(&:match?)
  def differs_count = rows.count(&:differs?)

  # The date the fund's figures are stored against — the run's end date, not the run itself, so
  # re-running the period finds the figures already typed in.
  def as_of_date = @allocation_run.end_date

  # The folios behind one row, largest first. Runs only when a reviewer opens a row, and is the
  # one query in this class that touches account_entries. Narrow select: this table has wide
  # json/text columns that dominate per-row memory.
  # @param name [String]
  # @return [Hash] rows: [[folio_id, commitment_name, amount_cents, entry_id, reporting_date]], total_count:
  def folios(name)
    scope = AccountEntry.where(fund_id: @fund.id, entity_id: @fund.entity_id,
                               allocation_run_id: @allocation_run.id,
                               reporting_date: @allocation_run.start_date..@allocation_run.end_date,
                               name: name, deleted_at: nil)
                        .not_cumulative.where.not(capital_commitment_id: nil)

    total_count = scope.count
    entries = scope.select(:id, :reporting_date, :capital_commitment_id, :commitment_name, :amount_cents)
                   .order(Arel.sql("ABS(amount_cents) DESC")).limit(MAX_FOLIOS).to_a
    folio_ids = CapitalCommitment.where(id: entries.map(&:capital_commitment_id)).pluck(:id, :folio_id).to_h

    rows = entries.map do |entry|
      [folio_ids[entry.capital_commitment_id], entry.commitment_name, entry.amount_cents,
       entry.id, entry.reporting_date]
    end

    { rows: rows, total_count: total_count }
  end

  private

  # Every row's formula, read for the names it depends on, resolved against the sheet's own
  # rows. A dependency is always another row here — "NAV" is built from "Capital Collected" and
  # the "Since Inception" lines, all of which the same run produced — so this costs no query at
  # all and lets a difference at one row be traced to the row carrying it.
  #
  # Both ways a formula names another entry are followed (see FormulaReferenceScanner): an
  # "@field" reference, and a name given as a string to since_inception / quarterly /
  # year_to_date / on_date or to a where(name:) filter.
  def link_dependencies(rows)
    by_name = rows.index_by(&:name)
    by_field = rows.index_by { |row| FundFormula.to_varable_name(row.name) }

    rows.each do |row|
      next if row.formula.blank?

      scan = FormulaReferenceScanner.new(row.formula).call
      signs = {}
      scan.field_names.each do |field|
        name = by_field[field]&.name
        signs[name] ||= scan.signs["@#{field}"] || 1 if name
      end
      scan.helper_calls.each { |call| signs[call.name] ||= scan.signs[call.source] || 1 if call.name }
      scan.name_filters.each { |name| signs[name] ||= 1 }
      # Names read this period by any route; only a name read solely at another date is marked
      # as such, or a figure the rule did read this period gets told it is not the one it read.
      same_period = signs.keys.to_set
      earlier = []
      scan.named_reads.each do |read|
        signs[read.name] ||= scan.signs[read.source] || 1
        read.same_period? ? same_period << read.name : earlier << read.name
      end
      earlier = earlier.uniq.reject { |name| same_period.include?(name) }

      deps = signs.keys.filter_map { |name| by_name[name] }.reject { |dep| dep.name == row.name }
      # Largest first, as everywhere else: which two or three carry the number is the question.
      row.dependencies = deps.sort_by { |dep| -dep.system_cents.to_d.abs }
      row.dependency_signs = signs
      row.earlier_periods = earlier
    end
  end

  # A final number: nothing else on the sheet is built from it, AND it is built from something.
  # A total that neither reads nor is read by anything stands alone — it is not the top of a
  # tree, and listing it under "top-level numbers only" is how that toggle came to show rows
  # that were not top-level in any sense a reviewer means.
  def mark_top_level(rows)
    # Only same-period edges. "Ending Unfunded Commitment" is read by NEXT period's "Beginning
    # Unfunded Commitment", which does not make it a feeder in this run — counting that edge
    # hid exactly the closing balances a reviewer looks for under "top-level numbers only".
    used = rows.flat_map { |row| row.dependencies.map(&:name) - Array(row.earlier_periods) }.to_set
    rows.each { |row| row.top = row.dependencies? && used.exclude?(row.name) }
  end

  # { name => [sum_cents, entry_count] }, folded out of the report's own pass 1. A run stamps
  # every entry it generates with the same reporting_date, but the fold is written over the
  # date anyway so a report spanning more than one date still totals correctly.
  def totals_by_name
    @report.name_date_totals.each_with_object({}) do |(name, _date, amount_cents, entry_count), result|
      next if name.blank?

      existing = result[name] ||= [0.to_d, 0]
      existing[0] += amount_cents.to_d
      existing[1] += entry_count.to_i
    end
  end

  # The fund's own figures for this date, in one query. Keyed by name only, matching how rows
  # are grouped; a figure carrying an entry_type from the folio check is ignored here.
  def figures_by_name
    TieOutFigure.fund_totals.as_of(as_of_date)
                .where(fund_id: @fund.id, entity_id: @fund.entity_id)
                .index_by(&:name)
  end

  # Sequence and formula text per entry name: the sequence so the sheet reads in the fund's own
  # order, the formula so a row can say what it is built from. One small query against
  # fund_formulas — not account_entries. A name produced by more than one formula takes the
  # earliest, which is where a reader would look for it.
  def sequence_by_name(names)
    return {} if names.empty?

    FundFormula.where(fund_id: @fund.id, name: names, deleted_at: nil)
               .order(:sequence)
               .pluck(:name, :sequence, :formula)
               .each_with_object({}) do |(name, sequence, formula), result|
      result[name] ||= { sequence: sequence, formula: formula }
    end
  end
end
