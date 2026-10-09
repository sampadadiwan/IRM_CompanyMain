# Turns a fund's fund-level account entries and its mapping into statement-account figures, the
# integrity checks and the Unmapped list. Pure: never writes. One calculator serves the mapping
# preview, the AI draft's reconciliation, the statements run and the drift banner, so their figures
# cannot disagree.
#
# Figures per account (natural sign, see FinancialStatementAccount), in cents:
#   period      — change over start..end
#   ytd         — change over fy_start..end
#   balance     — value at end
#   opening     — value at start - 1
#   ytd_opening — value at fy_start - 1
# A periodic pair (cumulative = false) sums its rows; a cumulative pair takes its latest row at a date.
#
# Only grouped SQL — account_entries rows are never loaded (CLAUDE.md, large-table hygiene).
# Worked examples H9, H10, E4, E5, E6, E7, E13, E14, E21, E24, X10 —
# openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementCalculator
  FS_ENTRY_TYPE = "Financial Statement".freeze
  # Statement lines are stored as account entries named "FS · <account>" so they can never share a
  # name with the fund's own entries (fund ratios and document templates look entries up by name).
  # Only the stored rows carry it: statements on screen, PDF and Excel print the account / layout label.
  FS_NAME_PREFIX = "FS · ".freeze
  FIGURE_KEYS = %w[period ytd balance opening ytd_opening].freeze
  # |difference| below one currency unit passes; exactly 1.00 fails (E4, E5)
  TOLERANCE_CENTS = 100
  CHECK_KEYS = %w[balance nav capital roll_forward].freeze
  CHECK_LABELS = { "balance" => "Balance", "nav" => "NAV tie-out", "capital" => "Partners' capital tie-out",
                   "roll_forward" => "Roll-forward", "stale_balance" => "Stale balance", "no_entries" => "No entries",
                   "mixed_cumulative" => "Mixed running total / movements" }.freeze

  Result = Struct.new(:figures, :checks, :unmapped, :warnings, :pairs, :assignments, keyword_init: true)
  # A draft mapping (AI suggestion) or the fund's saved one, in one shape.
  # accounts: { key => { "name", "account_type", "behaviour", "flip_sign" } }
  # rules:    [{ "entry_type", "name", "account_key", "excluded" }]
  Mapping = Struct.new(:accounts, :rules, keyword_init: true)

  attr_reader :fund, :start_date, :end_date, :fy_start, :mapping, :base, :setting

  def self.call(...)
    new(...).call
  end

  # @param mapping [Mapping, nil] nil loads the fund's saved mapping
  # @param base [Class] AccountEntry (the live database)
  def initialize(fund:, start_date:, end_date:, mapping: nil, base: AccountEntry, setting: nil)
    raise ArgumentError, "start date must be on or before end date" if start_date > end_date

    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @base = base
    # A fund previewed before set-up uses its default settings (unsaved)
    @setting = setting || FinancialStatementSetting.find_by(fund_id: fund.id) || FinancialStatementSetup.default_setting(fund)
    # E21: YTD starts at the fund's financial year start
    @fy_start = @setting.fiscal_year_start(end_date)
    # A draft (AI) mapping, else the fund's saved accounts and rules
    @mapping = mapping || self.class.saved_mapping(fund)
  end

  def call
    # 1. Figures per (entry type, name)
    pairs = pair_figures
    # 2. Routed to accounts by the rules; the rest is Unmapped
    figures, unmapped, assignments = map_pairs(pairs)
    # 3. Integrity checks over the account figures, then completeness warnings
    checks = self.class.checks(fund:, end_date:, figures:, accounts: mapping.accounts, setting:,
                               changes_account_keys: self.class.changes_account_keys(fund), base:)
    Result.new(figures:, unmapped:, warnings: @warnings, pairs:, assignments:, checks: checks + warning_checks(pairs, assignments))
  end

  # Completeness warnings, in the checks' shape with status "warning": they never block Lock, but the
  # Lock popup lists them for confirmation (V10–V12).
  # Worked examples E13, E29, E30 — openspec/changes/fund-financial-statements/design.md#worked-examples
  def warning_checks(pairs, assignments)
    warnings = []
    # V10 stale balance (E29): a running total feeding an account with nothing dated in the period
    assignments.each do |pair, rule|
      next if rule["excluded"]

      latest = @latest_cumulative_dates[pair]
      next unless latest && latest < start_date && !pairs[pair]["balance"].zero?

      account = mapping.accounts[rule["account_key"]]
      warnings << warning("stale_balance", "#{account&.dig('name') || pair.join(' · ')}: #{pair.join(' · ')} last value " \
                                           "#{I18n.l(latest)} (#{format_amount(pairs[pair]['balance'])}); nothing dated #{I18n.l(start_date)} – #{I18n.l(end_date)}")
    end
    # V11 no entries (E30): an account placed on a statement that nothing feeds
    fed = assignments.values.reject { |r| r["excluded"] }.to_set { |r| r["account_key"] }
    placed_account_keys.each do |key|
      next if fed.include?(key) || mapping.accounts[key].nil?

      warnings << warning("no_entries", "#{mapping.accounts[key]['name']}: no entries feed this line")
    end
    # V12 mixed running total / movements (E13)
    @warnings.select { |w| w["type"] == "mixed_cumulative" }.each do |w|
      warnings << warning("mixed_cumulative", "#{w['entry_type']} · #{w['name']}: stored both as a running total and as movements; the running total is used")
    end
    warnings
  end

  # The fund's saved accounts and rules as a Mapping (keys are account ids)
  def self.saved_mapping(fund)
    # Accounts keyed by id, in the calculator's plain-hash shape
    accounts = FinancialStatementAccount.where(fund_id: fund.id).to_h do |a|
      [a.id, { "name" => a.name, "account_type" => a.account_type, "behaviour" => a.behaviour, "flip_sign" => a.flip_sign }]
    end
    # Rules point at account ids ("" name = any name)
    rules = FinancialStatementMappingRule.where(fund_id: fund.id).map do |r|
      { "entry_type" => r.entry_type, "name" => r.name.to_s, "account_key" => r.financial_statement_account_id, "excluded" => r.excluded }
    end
    Mapping.new(accounts:, rules:)
  end

  # Every fund-level (entry type, name) with its figures, for the AI draft's entry list.
  def entry_totals
    # Same grouped queries as the statements; only the two figures the AI needs
    pair_figures.map { |(entry_type, name), f| { "entry_type" => entry_type, "name" => name, "balance" => f["balance"], "period" => f["period"] } }
  end

  # The four integrity checks over a set of account figures. Used on fresh calculator figures and
  # on figures read back from a run's "Financial Statement" entries (FinancialStatementRefreshJob).
  # Each check: { "key", "status" => passed|failed|skipped, "diff" (cents), "note" }
  def self.checks(fund:, end_date:, figures:, accounts:, setting:, changes_account_keys:, base: AccountEntry)
    # Partners' capital at the end, including the P&L result since inception
    capital_total = capital_total(figures, accounts, "balance")
    assets = sum_type(figures, accounts, "asset", "balance")
    liabilities = sum_type(figures, accounts, "liability", "balance")

    checks = []
    # Balance: assets - liabilities = partners' capital (X10, E4, E5)
    checks << check("balance", assets - liabilities - capital_total)

    # NAV tie-out: partners' capital = the fund's NAV entry at the end date (E6)
    checks << if setting.nav_configured?
                nav = latest_value(base, fund, setting.nav_entry_type, setting.nav_entry_name, end_date, folio: false)
                nav.nil? ? skipped("nav", "Skipped — no NAV entry on or before #{I18n.l(end_date)}") : check("nav", capital_total - nav)
              else
                skipped("nav", "Skipped — not configured")
              end

    # Partners' capital tie-out: partners' capital = sum of investors' capital entries (E7)
    checks << if setting.capital_configured?
                folio_total = latest_value(base, fund, setting.capital_entry_type, setting.capital_entry_name, end_date, folio: true)
                check("capital", capital_total - folio_total.to_d)
              else
                skipped("capital", "Skipped — not configured")
              end

    # Roll-forward: opening capital + the Changes statement's movements = closing capital.
    # Catches a Changes layout that misses a capital movement.
    checks << if changes_account_keys.nil?
                skipped("roll_forward", "Skipped — no rows on the Statement of Changes in Partners' Capital")
              else
                opening = capital_total(figures, accounts, "opening")
                movements = changes_account_keys.sum { |key| figures.dig(key, "period").to_d }
                movements += net_result(figures, accounts, "period") if changes_includes_net_result?(fund)
                check("roll_forward", opening + movements - capital_total)
              end
    checks
  end

  # Partners' capital at a point = capital accounts + the P&L result accumulated since inception.
  # The second part is how the P&L closes into capital without a retained-earnings entry.
  def self.capital_total(figures, accounts, point)
    sum_type(figures, accounts, "capital", point) + net_result(figures, accounts, point)
  end

  # Income - expenses + gains, at a point (balance/opening/ytd_opening = since inception) or over a
  # column (period/ytd)
  def self.net_result(figures, accounts, key)
    sum_type(figures, accounts, "income", key) - sum_type(figures, accounts, "expense", key) + sum_type(figures, accounts, "gain_loss", key)
  end

  def self.sum_type(figures, accounts, account_type, key)
    accounts.sum(0.to_d) { |akey, a| a["account_type"] == account_type ? figures.dig(akey, key).to_d : 0.to_d }
  end

  def self.check(key, diff)
    { "key" => key, "status" => diff.abs < TOLERANCE_CENTS ? "passed" : "failed", "diff" => diff.to_d.round(2).to_s }
  end

  def self.warning(key, note)
    { "key" => key, "status" => "warning", "diff" => nil, "note" => note }
  end

  def self.skipped(key, note)
    { "key" => key, "status" => "skipped", "diff" => nil, "note" => note }
  end

  # Account keys placed on the Changes statement (nil when it has no account rows: check skipped)
  def self.changes_account_keys(fund)
    keys = FinancialStatementLayoutRow.joins(:definition)
                                      .where(fund_id: fund.id, row_type: "account", financial_statement_definitions: { kind: "changes_in_capital" })
                                      .distinct.pluck(:financial_statement_account_id)
    keys.empty? ? nil : keys
  end

  def self.changes_includes_net_result?(fund)
    FinancialStatementLayoutRow.joins(:definition)
                               .exists?(fund_id: fund.id, row_type: "net_result", financial_statement_definitions: { kind: "changes_in_capital" })
  end

  # Latest value of an entry type + name on or before date: the fund-level row(s), or the sum over
  # folios of each folio's latest row. nil when there is none.
  def self.latest_value(base, fund, entry_type, name, date, folio:)
    scope = base.where(fund_id: fund.id, entry_type:, name:, deleted_at: nil).where(reporting_date: ..date)
    # Folio rows for the capital tie-out, the fund-level row for NAV
    scope = folio ? scope.where.not(capital_commitment_id: nil) : scope.where(capital_commitment_id: nil)
    # Latest date per folio (or for the fund), joined back to sum the rows on that date
    group_col = folio ? :capital_commitment_id : :fund_id
    latest = scope.group(group_col).select("#{group_col} AS grp, MAX(reporting_date) AS max_date")
    # nil (not 0) so a missing NAV entry skips the check instead of failing it
    return nil unless scope.exists?

    scope.joins("INNER JOIN (#{latest.to_sql}) latest ON latest.grp = account_entries.#{group_col} AND latest.max_date = account_entries.reporting_date")
         .sum(:amount_cents).to_d
  end

  private

  def warning(key, note)
    self.class.warning(key, note)
  end

  def format_amount(cents)
    ActiveSupport::NumberHelper.number_to_delimited((cents.to_d / 100).round(2).to_s("F"))
  end

  # Accounts placed on any statement of a saved mapping (a draft AI mapping has no layout)
  def placed_account_keys
    return [] unless mapping.accounts.keys.all?(Integer)

    FinancialStatementLayoutRow.where(fund_id: fund.id, row_type: "account").distinct.pluck(:financial_statement_account_id)
  end

  # Fund-level entries the statements read: never folio rows (E3), never the statements' own
  # output (E17), never soft-deleted rows
  def scope
    # E3: capital_commitment_id IS NULL drops folio rows; E17: our own "Financial Statement" lines are left out
    base.where(fund_id: fund.id, capital_commitment_id: nil, deleted_at: nil).where.not(entry_type: FS_ENTRY_TYPE)
  end

  # { [entry_type, name] => { "period", "ytd", "balance", "opening", "ytd_opening", "cumulative" } }
  def pair_figures
    @warnings = []
    # NULL cumulative (legacy rows) counts as periodic, as the column default false means
    periodic = scope.where(cumulative: [false, nil])
    # Q1–Q3: periodic sums over the period, the year to date and since inception (E14: both ends included)
    period = periodic.where(reporting_date: start_date..end_date).group(:entry_type, :name).sum(:amount_cents)
    ytd = periodic.where(reporting_date: fy_start..end_date).group(:entry_type, :name).sum(:amount_cents)
    since_inception = periodic.where(reporting_date: ..end_date).group(:entry_type, :name).sum(:amount_cents)
    # Q4: latest cumulative value per pair at the three points
    cum_end = latest_cumulative(end_date)
    cum_open = latest_cumulative(start_date - 1)
    cum_ytd_open = latest_cumulative(fy_start - 1)
    # When each running total was last reported (stale balance warning, V10)
    @latest_cumulative_dates = scope.where(cumulative: true).where(reporting_date: ..end_date).group(:entry_type, :name).maximum(:reporting_date)

    # Every pair with any row up to the end date
    keys = (since_inception.keys + cum_end.keys).uniq
    keys.to_h do |key|
      figures = if cum_end.key?(key)
                  # H9 / E13: a pair with cumulative rows uses them only; mixing is flagged
                  @warnings << { "type" => "mixed_cumulative", "entry_type" => key[0], "name" => key[1] } if since_inception.key?(key)
                  balance = cum_end[key].to_d
                  opening = cum_open[key].to_d
                  ytd_opening = cum_ytd_open[key].to_d
                  { "period" => balance - opening, "ytd" => balance - ytd_opening, "balance" => balance,
                    "opening" => opening, "ytd_opening" => ytd_opening, "cumulative" => true }
                else
                  # H10: a periodic pair's balance is its sum since inception
                  balance = since_inception[key].to_d
                  p = period[key].to_d
                  y = ytd[key].to_d
                  { "period" => p, "ytd" => y, "balance" => balance, "opening" => balance - p,
                    "ytd_opening" => balance - y, "cumulative" => false }
                end
      [key, figures]
    end
  end

  # Latest cumulative value of each pair on or before date (max date per pair, joined back and summed)
  def latest_cumulative(date)
    cumulative = scope.where(cumulative: true).where(reporting_date: ..date)
    # Subquery: the latest reporting date of each pair on or before date
    latest = cumulative.group(:entry_type, :name).select("entry_type AS l_type, name AS l_name, MAX(reporting_date) AS max_date")
    cumulative.joins("INNER JOIN (#{latest.to_sql}) latest ON latest.l_type = account_entries.entry_type " \
                     "AND latest.l_name = account_entries.name AND latest.max_date = account_entries.reporting_date")
              .group(:entry_type, :name).sum(:amount_cents)
  end

  # Routes each pair to an account by the rules: exact name beats any name (H5); Excluded pairs are
  # dropped (E2); a non-zero pair with no rule is Unmapped (H6), a zero one is not (E22).
  def map_pairs(pairs)
    exact = {}
    any_name = {}
    mapping.rules.each do |rule|
      if rule["name"].to_s.empty?
        any_name[rule["entry_type"]] = rule
      else
        exact[[rule["entry_type"], rule["name"]]] = rule
      end
    end

    figures = Hash.new { |h, k| h[k] = FIGURE_KEYS.index_with { 0.to_d } }
    unmapped = []
    # [entry_type, name] => the rule that took it (the mapping screen's per-rule preview)
    assignments = {}
    pairs.each do |(entry_type, name), f|
      # H5: an exact-name rule wins; H4: otherwise the entry type's any-name rule catches new names
      rule = exact[[entry_type, name]] || any_name[entry_type]
      assignments[[entry_type, name]] = rule if rule
      if rule.nil?
        # E22: a pair that nets to zero (period and balance) is not worth mapping
        next if f["period"].zero? && f["balance"].zero?

        # H6: non-zero with no rule -> listed under Unmapped (blocks Lock, X8)
        unmapped << { "entry_type" => entry_type, "name" => name, "period" => f["period"], "balance" => f["balance"] }
        next
      end
      # E2: excluded on purpose — counted nowhere, not Unmapped either
      next if rule["excluded"]

      account = mapping.accounts[rule["account_key"]]
      next unless account

      # E24: flip turns a raw sum into the account's natural sign
      sign = account["flip_sign"] ? -1 : 1
      FIGURE_KEYS.each { |k| figures[rule["account_key"]][k] += sign * f[k] }
    end
    # Every account gets figures, even with no entries (shows 0, not a missing line)
    mapping.accounts.each_key { |key| figures[key] }
    [figures.to_h, unmapped.sort_by { |u| [u["entry_type"], u["name"]] }, assignments]
  end
end
