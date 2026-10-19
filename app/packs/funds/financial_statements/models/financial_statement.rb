# One statement set of a fund for a period: every statement of the fund (core + schedules),
# generated together by one statements run.
#
# status is stored (draft | locked). Inside Draft the state is derived from the statements run:
#   generating — run queued/running, or finished but not refreshed yet
#   failed     — run ended with an error
#   ready      — run succeeded and FinancialStatementRefreshJob stored checks and unmapped count
# Locking copies every figure, the rendered statements and the mapping into frozen_data: the
# published truth used for the locked view, downloads, comparatives and the drift banner.
# Worked examples H12, H15, H18, E1, E9, E10, E11, E26, X8, X9 —
# openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatement < ApplicationRecord
  STATUSES = %w[draft locked].freeze
  # Figures compared for drift, and how a non-main one is named in the banner
  DRIFT_COLUMNS = %w[period ytd balance].freeze
  DRIFT_COLUMN_LABELS = { "period" => "period", "ytd" => "year to date", "balance" => "balance" }.freeze

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :accounting_allocation_run, class_name: "AllocationRun", optional: true
  belongs_to :statements_allocation_run, class_name: "AllocationRun", optional: true
  belongs_to :locked_by, class_name: "User", optional: true

  validates :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :end_date, uniqueness: { scope: %i[fund_id start_date], message: "already has statements for this period" }
  validate :start_on_or_before_end

  scope :locked, -> { where(status: "locked") }
  scope :drafts, -> { where(status: "draft") }
  # Statement sets whose period overlaps start..end
  scope :overlapping, ->(start_date, end_date) { where("start_date <= ? AND end_date >= ?", end_date, start_date) }

  def locked?
    status == "locked"
  end

  def draft?
    status == "draft"
  end

  # generating | failed | ready | locked (see class comment)
  def state
    return "locked" if locked?

    # Pending / blank = still running; Success = done; anything else is the engine's error message
    run_status = statements_allocation_run&.status
    return "failed" if statements_allocation_run.nil? || (run_status.present? && %w[Pending Success].exclude?(run_status))
    return "ready" if run_status == "Success" && refreshed_at.present?

    "generating"
  end

  def run_error
    statements_allocation_run&.status if state == "failed"
  end

  def period_label
    "#{I18n.l(start_date)} – #{I18n.l(end_date)}"
  end

  def to_s
    "#{fund.name}: #{period_label}"
  end

  def setting
    @setting ||= FinancialStatementSetting.find_by(fund_id:) || FinancialStatementSetup.default_setting(fund)
  end

  def fy_start
    setting.fiscal_year_start(end_date)
  end

  def checks_list
    Array(checks)
  end

  def checks_passed_count
    integrity_checks.count { |c| c["status"] == "passed" }
  end

  def failed_checks
    checks_list.select { |c| c["status"] == "failed" }
  end

  # The four integrity checks (passed / failed / skipped)
  def integrity_checks
    checks_list.reject { |c| c["status"] == "warning" }
  end

  # Completeness warnings (V10–V12): shown, confirmed on Lock, never blocking
  def warning_checks
    checks_list.select { |c| c["status"] == "warning" }
  end

  # [lockable, reason] — X8 (unmapped), X9 (failed check), and only a ready draft
  def lockable_with_reason
    return [false, "These statements are already locked."] if locked?
    return [false, "Wait for the statements to finish generating."] unless state == "ready"
    # X8: entries nobody mapped keep Lock disabled
    return [false, "Map or exclude #{unmapped_count} #{unmapped_count == 1 ? 'entry' : 'entries'} before locking."] if unmapped_count.positive?

    # X9: any failed check refuses the lock (a direct request too); skipped checks don't
    failed = failed_checks
    if failed.any?
      labels = failed.map { |c| FinancialStatementCalculator::CHECK_LABELS[c["key"]] }
      return [false, "Checks must pass before locking: #{labels.to_sentence} failed."]
    end
    [true, nil]
  end

  def lockable?
    lockable_with_reason.first
  end

  # Account figures (cents, natural sign) keyed by account id: the frozen copy once locked,
  # otherwise read back from this set's "Financial Statement" entries.
  def figures
    @figures ||= locked? ? self.class.figures_from_json(frozen_data&.dig("figures")) : figures_from_entries
  end

  # The draft's figures, from the entries its latest statements run wrote (only 3 small columns
  # selected — CLAUDE.md large-table hygiene). The other two figures of each account are derived.
  def figures_from_entries
    return {} unless statements_allocation_run_id

    # Behaviour decides which two figures are derived
    accounts = FinancialStatementAccount.where(fund_id:).pluck(:id, :behaviour).to_h
    figures = Hash.new { |h, k| h[k] = {} }
    AccountEntry.where(fund_id:, allocation_run_id: statements_allocation_run_id, deleted_at: nil, capital_commitment_id: nil,
                       entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE, reporting_date: end_date)
                .pluck(:amount_cents, :json_fields).each do |amount, json|
      # Some adapters hand JSON columns back as text
      json = JSON.parse(json) if json.is_a?(String)
      next unless json && json["fs_account_id"]

      figures[json["fs_account_id"].to_i][json["column"]] = amount.to_d
    end
    figures.each { |account_id, f| self.class.complete_figures!(f, accounts[account_id]) }
    figures.to_h
  end

  # A movement account stores period/ytd/balance, a balance account balance/opening/ytd_opening;
  # the other two follow (opening = balance - period, ...)
  def self.complete_figures!(figures, behaviour)
    balance = figures["balance"].to_d
    if behaviour == "balance"
      figures["period"] ||= balance - figures["opening"].to_d
      figures["ytd"] ||= balance - figures["ytd_opening"].to_d
    else
      figures["opening"] ||= balance - figures["period"].to_d
      figures["ytd_opening"] ||= balance - figures["ytd"].to_d
    end
    FinancialStatementCalculator::FIGURE_KEYS.each { |k| figures[k] = figures[k].to_d }
    figures
  end

  def self.figures_from_json(json)
    (json || {}).to_h { |account_id, f| [account_id.to_i, f.transform_values(&:to_d)] }
  end

  # Fresh figures from current data (drift banner, comparatives with no locked source)
  def current_result
    @current_result ||= FinancialStatementCalculator.call(fund:, start_date:, end_date:, setting:)
  end

  # Lines whose current figure differs from the frozen copy by one unit or more (E9, E10).
  # Empty for drafts. Each: { "account", "column", "locked", "current" } (cents, display sign).
  def drift
    return [] unless locked?

    @drift ||= begin
      accounts = FinancialStatementAccount.where(fund_id:).index_by(&:id)
      # E9 / E10: recomputed from today's entries, compared with what was frozen at lock
      current = current_result.figures
      figures.filter_map do |account_id, locked_figures|
        account = accounts[account_id]
        next unless account

        # Every figure a statement can show (an edit outside the period still changes YTD / balance);
        # the one reported is the account's main figure when it changed, else the first that did
        main = account.behaviour == "movement" ? "period" : "balance"
        changed = [main, *(DRIFT_COLUMNS - [main])].select do |c|
          # Same one-unit tolerance as the checks
          (locked_figures[c].to_d - current.dig(account_id, c).to_d).abs >= FinancialStatementCalculator::TOLERANCE_CENTS
        end
        next if changed.empty?

        column = changed.first
        locked_value = locked_figures[column].to_d
        current_value = current.dig(account_id, column).to_d

        sign = FinancialStatementAccount::NEGATIVE_DISPLAY_TYPES.include?(account.account_type) ? -1 : 1
        label = column == main ? account.name : "#{account.name} (#{DRIFT_COLUMN_LABELS[column]})"
        { "account" => label, "column" => column, "locked" => sign * locked_value, "current" => sign * current_value }
      end
    end
  end

  def drifted?
    drift.any?
  end

  # For the Statements list: drift needs a full calculation per locked set, so the list reuses a
  # result for 10 minutes (the statement page itself always recomputes)
  def drifted_cached?
    return false unless locked?

    Rails.cache.fetch("financial_statement_drift/#{id}/#{locked_at.to_i}", expires_in: 10.minutes) { drifted? }
  end

  # The rendered statements (one per definition, rows with column values). Locked sets render their
  # frozen copy so later layout edits never change what was published.
  def statements
    # E10: a locked set always renders (and downloads) its frozen copy, never recomputed figures
    @statements ||= locked? && frozen_data&.dig("statements") ? frozen_data["statements"] : FinancialStatementPresenter.new(self).statements
  end

  private

  def start_on_or_before_end
    errors.add(:end_date, "must be on or after the start date") if start_date && end_date && start_date > end_date
  end
end
